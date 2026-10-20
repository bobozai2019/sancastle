"""Summarize current-main traces without conflating CPU delivery and GPU time."""
import bisect
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/unified_edit_pipeline"))
from analyze_shovel_latency import stats


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def summarize(directory):
    runs = {}
    for path in sorted(directory.glob("*.analysis.json")):
        raw_path = path.with_suffix("").with_suffix(".json")
        raw, analysis = read(raw_path), read(path)
        manifest_path = raw_path.with_suffix(".manifest.json")
        manifest = read(manifest_path)
        events = raw["observations"]["timeline"]["events"]
        frames = raw["frames"]
        times = [r["at_us"] for r in frames]

        def phase(at):
            index = bisect.bisect_right(times, at) - 1
            return frames[index]["phase"] if index >= 0 else "warmup"

        batch_slots = {
            e["key"]: e["detail"]["slot"]
            for e in events if e["event"] == "batch_queued"
        }
        witness = None
        # A CPU_RECLAIM slot has already been consumed but its deferred FREE
        # acknowledgement has not run. Retain one full, identified cycle.
        for index, event in enumerate(events):
            if event["event"] != "slot_blocked" or phase(event["at_us"]) != "playing_drag":
                continue
            states = event["detail"]["states"]
            if 4 not in states:
                continue
            for free_index in range(index + 1, min(index + 80, len(events))):
                free = events[free_index]
                slot = batch_slots.get(free["key"])
                if free["event"] != "slot_free" or slot is None or states[slot] != 4:
                    continue
                prior = [e for e in events[:index] if e["key"] == free["key"] and e["event"] in
                         ["readback_callback", "consume_begin", "settle_end", "retire_render"]]
                next_build = next((e for e in events[free_index + 1:]
                                   if e["event"] == "batch_queued" and e["detail"]["slot"] == slot), None)
                witness = {"slot": slot, "previous_batch": free["key"],
                           "events": prior + [event, free] + ([next_build] if next_build else []),
                           "free_to_next_queued_ms": (next_build["at_us"] - free["at_us"]) / 1000 if next_build else None}
                break
            if witness:
                break

        phases = {}
        for tag in ["playing_idle", "playing_drag", "paused_drag"]:
            fields = analysis["phase_ms"].get(tag, {})
            selected = {key: fields[key] for key in [
                "frame", "command_queue", "command_to_settled", "callback_to_slot_free",
                "free_to_next_acquire", "pump_cpu", "height_apply_cpu",
                "height_apply_cpu_per_frame_overlap", "shape_cpu_per_frame_overlap",
                "move_cpu", "pick_cpu", "preview_submit_cpu",
                "gpu_batch_kind_0", "gpu_batch_kind_1",
            ] if key in fields}
            selected["rates"] = analysis["rates"].get(tag, {})
            selected["record_cpu_by_kind_ms"] = {
                str(kind): stats([b["ms"]["record_cpu"] for b in analysis["batches"]
                                  if b["phase"] == tag and b["kind"] == kind])
                for kind in [0, 1]
            }
            if raw["sampling"]:
                selected["viewport_gpu_ms"] = stats([r["render_gpu_ms"] for r in frames if r["phase"] == tag])
            phases[tag] = selected
        runs[raw_path.stem] = {
            "source": str(raw_path.resolve()), "sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
            "measurement_valid": analysis["measurement_valid"],
            "source_integrity": analysis["source_integrity"],
            "configuration": raw["observations"]["current_probe"],
            "hardware": {key: raw["runtime"][key] for key in ["engine", "adapter", "driver", "window", "vsync"]},
            "cpu": "Intel Core i5-9300H, 4 cores / 8 logical processors",
            "background_before": manifest["background_processes_before"],
            "background_after": manifest["background_processes_after"],
            "input_rejections": analysis["input_rejections"],
            "terminal_outcomes": dict(Counter(str(e["detail"]["outcome"]) for e in events if e["event"] == "result_taken")),
            "gpu_ms": analysis["gpu_ms"], "phases": phases,
            "slot_turnaround_witness": witness,
        }
    findings = [
        {
            "id": "input_turnaround", "confidence": "C3",
            "claim": "水tick和编辑共用三个工作槽。完成回执已消费后，retire的deferred确认尚未把CPU_RECLAIM变为FREE，pump先因no_slot退出；FREE后通常等下一帧pump，增加输入到录制/结算的等待。",
            "evidence": "各run的slot_turnaround_witness、command_queue、callback_to_slot_free、free_to_next_acquire与paused_drag对照。",
            "source": ["scripts/simulation/unified_edit/layout.gd:19",
                       "scripts/simulation/unified_edit/pipeline.gd:305",
                       "scripts/simulation/unified_edit/pipeline.gd:434"],
            "counterevidence_limit": "这是输入响应延迟的直接证据。no_slot也可能出现在约60FPS运行中，不能单凭它归因所有画面长帧；CPU回执时间不等于屏幕呈现时间或GPU结束时间。",
        },
        {
            "id": "main_thread_work", "confidence": "C3",
            "claim": "GPU命令录制与HeightMapShape更新都有实际主线程耗时，给编辑帧增加压力。水tick在CPU上固定录制64轮子步，每轮3个水阶段和9个耦合阶段；实际子步数由GPU间接派发决定，零工作量派发仍有CPU录制。",
            "evidence": "record_cpu_by_kind_ms（0为编辑，1为水tick）、pump_cpu、shape_cpu_per_frame_overlap；事件thread均可查原始时间线。",
            "source": ["scripts/simulation/unified_edit/water.gd:132",
                       "scripts/simulation/unified_edit/coupled.gd:61",
                       "scripts/simulation/unified_edit/cfl_decide.glsl:39",
                       "scripts/simulation/unified_edit/height.gd:164",
                       "scripts/simulation/unified_edit/height_surface.gd:35"],
            "counterevidence_limit": "record_cpu为调用墙钟，可含驱动等待和抢占；父子跨度不能相加。尚未把64轮的每个CPU调用分开计时，不能给它们分配完整长帧占比。",
        },
        {
            "id": "current_gpu_cost", "confidence": "C3",
            "claim": "当前主场景实际使用策略2；采样到的单笔编辑水响应约1.1ms，其中速度/能量归约约0.74ms。常规水tick约1.3ms，视口绘制约11ms。旧文档中的20–50ms水响应不是本轮默认路径。",
            "evidence": "dig_wet_gpu与fill_wet_gpu的gpu_ms、configuration.policy、viewport_gpu_ms。",
            "source": ["scripts/simulation/unified_edit/water_response.gd:87",
                       "shaders/simulation/edit_validation/water_velocity_prefetch.glsl:3"],
            "counterevidence_limit": "水阶段每process帧仅采样首笔；默认策略2的结论不覆盖手动启用策略3、其他场景或异常大笔刷。没有原生GPU/CPU校准时间线，不能严格加总各分位数或归因Present/fence。",
        },
        {
            "id": "frame_variability", "confidence": "C3",
            "claim": "短测复现约20–45ms帧间隔波动与输入等待，但低采样复测能接近60FPS。初轮与复测不能当作优化前后效果；本轮没有修改运行实现。",
            "evidence": "dig_wet_host、fill_wet_host、dig_wet_host_repeat；保留所有原始数据与进程快照。",
            "counterevidence_limit": "首轮开始时另有游戏进程，结束快照时已退出；其他轮仅见编辑器。没有持续系统负载/温度/频率采样。GPU详细轮空闲阶段也有686ms离群帧，该尖峰不能归因挖沙；用户的真实鼠标轨迹、长期/高力度操作仍未复现。",
        },
    ]
    result = {
        "scope": "定位当前主场景默认挖填；仅新增诊断工具，未修改产品实现。",
        "runs": runs, "findings": findings,
        "next_fix_order": [
            "优先研究完成回执、真实retire确认与pump的帧内顺序，减少确认后空等；保留所有权证明，不直接强制FREE。",
            "降低水tick在主线程录制64轮的成本，并对实际形状更新设置可验证的消费预算；保持碰撞最终收敛。",
            "并行化剩余速度归约可降低GPU固定成本，但约0.74ms收益上限不足以单独解释或消除所有长帧。",
        ],
        "measurement_limits": [
            "固定相机/初态和每帧一次输入；不同运行帧速改变输入墙钟节奏及模拟演化，不能视为逐位同状态A/B。",
            "暂停段继续同一场景而非恢复同一水沙状态，作为调度对照而非数值等价验证。",
            "P95为短窗口样本，不代表长期p99；入队到结算不是输入到显示器扫出延迟。",
            "采样诊断本身有开销；GPU详细轮只用于阶段成本，帧时间优先参考低采样轮。",
        ],
    }
    destination = directory / "diagnosis.json"
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, run in runs.items():
        p = run["phases"]["playing_drag"]
        print(name, json.dumps({
            "valid": run["measurement_valid"], "frame": p["frame"],
            "queue": p.get("command_queue"), "settled": p.get("command_to_settled"),
            "record_cpu_by_kind_ms": p["record_cpu_by_kind_ms"],
            "shape": p.get("shape_cpu_per_frame_overlap"),
            "blocked": p["rates"].get("slot_blocked_pumps"),
        }, ensure_ascii=False))
    print(destination.resolve())


if __name__ == "__main__":
    summarize(Path(sys.argv[1]).resolve())
