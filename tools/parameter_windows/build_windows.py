"""Build scene-authored parameter controls; no runtime UI construction."""
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parents[2]
ROWS = []


def add(id, group, label, default, low=0, high=1, step=.01, mode="live", target="", kind="number", **extra):
    ROWS.append(dict(id=id, group=group, label=label, default=default, min=low, max=high,
                     step=step, mode=mode, target=target, kind=kind, **extra))


for id, label, default, low, high, step in [
    ("dig_amount_m3", "挖沙量 m³", .1,.01,1,.01), ("fill_amount_m3","填沙／流沙量 m³",.1,.01,1,.01),
    ("radius_m","普通刷半径 m",.75,.125,4,.125), ("strength","普通刷力度",1,0,1,.05),
    ("castle_height","城堡标高 m",.7,.5,1,.05),("castle_scale","城堡缩放",1,1,1.5,.05),
    ("castle_yaw","城堡朝向 °",0,-180,180,15), ("wall_height","墙高 m",.3,.15,.6,.05),
    ("wall_bottom","墙底宽 m",1,1,2,.125),("wall_top","墙顶宽 m",.5,.5,1.5,.125),
    ("shovel_depth","铲沟深 m",.15,.05,.3,.05),("shovel_width","铲沟宽 m",.5,.5,1,.125),
    ("shovel_shoulder","单侧堆沙宽 m",.5,.5,1,.125), ("adjust_radius","平滑／压实半径 m",.75,.125,4,.125),
    ("adjust_strength","平滑／压实力度",1,0,1,.05), ("signed_speed_m_s","推拉水力度 m/s",.25,-1,1,.05)]:
    add(id,"tools",label,default,low,high,step,"next","tool")
add("water_policy","tools","水响应策略",2,0,3,1,"next","tool","choice",options=["保持水深","位移","动量 B","连通排水＋速度"])
add("gravel_count","props","单次碎石数量",16,1,128,1,"next","tool","int")
add("manual_wave_amplitude_m","water","下次造浪幅度 m",.1,0,.2,.01,"next","entry")
add("manual_wave_duration_s","water","下次造浪持续 s",3,.5,6,.1,"next","entry")
add("wave_retention","water","保波程度",0,0,1,.1,"restart","numerics")
add("solver","water","水求解器",1,0,1,1,"restart","numerics","choice",options=["一阶 Rusanov","二阶 MUSCL"])
for key,label,default,low,high,step in [
    ("mean_level_m","边界平均水位 m",.1,-2,2,.01), ("amplitude_m","边界水位振幅 m",.11,0,.6,.01),
    ("omega_rad_s","边界角频率 rad/s",.35,-10,10,.01), ("phase_rad","边界相位 rad",0,-1000,1000,.1),
    ("period_s","边界周期 s",16,.1,3600,.1)]:
    add("boundary_"+key,"water",label,default,low,high,step,"restart","boundary",field=key)
for key,label,default,low,high,step in [
    ("capacity_per_speed_s","携沙容量系数",.003,0,.03,.0001),
    ("erosion_rate_per_s","侵蚀速率 /s",.7295628483661365,0,3,.01),
    ("deposition_rate_per_s","沉积速率 /s",.2419645313921744,0,3,.01),
    ("wet_rate_per_s","湿润速率 /s",1.5,0,5,.05), ("dry_rate_per_s","干燥速率 /s",.07,0,1,.01),
    ("diffusion_per_s","湿度扩散 /s",4,0,8,.1), ("residual_wetness","残余湿度",.05,0,1,.01),
    ("soak_depth_m","饱和水深 m",.06,.001,.5,.001), ("dry_depth_m","干湿水深阈值 m",.001,.0001,.02,.0001),
    ("compact_rate_per_s","自然压实速率 /s",.05,0,1,.01), ("relax_rate_per_s","塌落松弛速率 /s",15,0,30,.5),
    ("dry_repose_tan","干沙安息坡度 tan",.674,.1,2,.01), ("wet_repose_tan","湿沙安息坡度 tan",1,.1,2,.01),
    ("compaction_repose_gain","压实坡度增益",.3,0,1,.01), ("min_drop_m","塌落最小落差 m",.0005,.0001,.01,.0001)]:
    add(key,"sand",label,default,low,high,step,"restart","coupling")
add("ordinary_cohesion_yield_height_m","sand","普通沙内聚高度 m",0,0,2,.05,"restart","environment")
for id,label,default in [("enable_erosion","水沙侵蚀与材料演化",True),("enable_brush_water","编辑水响应能力",True)]:
    add(id,"sand",label,default,mode="restart",target="simulation",kind="bool")

# Only uniforms used by the active formal render paths; textures/ownership inputs stay private.
for group,node,items in [
    ("water","GpuWaterSurface",[
        ("rdc_normal_gain","水面法线强度",0,3,.05),("rdc_normal_scale","水面法线尺度",0,2,.01),
        ("rdc_time_scale","水纹运动倍率",0,4,.05),("rdc_refraction_scale","折射强度",0,.05,.001),
        ("rdc_distance_scale","吸收距离倍率",0,4,.05),("rdc_surface_gain","表面颜色强度",0,3,.05),
        ("natural_reflection_gain","反射强度",0,3,.05),("natural_glint_gain","碎闪强度",0,2,.01),
        ("natural_glint_exponent","碎闪锐度",0,4096,1),("natural_scatter_gain","散射强度",0,3,.05),
        ("natural_main_foam_gain","水面白沫强度",0,3,.05)]),
    ("sand","GpuSandTerrain",[("natural_caustic_strength","沙底亮纹强度",0,2,.05),
        ("natural_caustic_softness","亮纹柔和度",0,1,.05),("natural_caustic_uv_scale","亮纹尺度",.25,4,.05),
        ("rdc_caustic_scale","当前亮纹纹理密度 /m",.01,4,.01),("rdc_caustic_depth_decay","亮纹深度衰减",0,5,.05),("rdc_caustic_time_scale","亮纹运动倍率",0,4,.05)]),
]:
    for field,label,lo,hi,step in items:
        add("visual_"+field,group,label,0,lo,hi,step,target="uniform",node=node,field=field)
for node,items in [("PrototypeFrontFoamDense",[("natural_fine_gain","细碎白沫强度",0,3,.05),("target_diameter_px","白沫像素直径",0,8,.25),("splat_half_width_m","白沫半宽 m",.001,.2,.001),("natural_cluster_strength","白沫聚簇强度",0,1,.05)]),("ShoreContactOverlay",[("natural_contact_gain","水沙接触强度",0,3,.05),("natural_contact_shape_scale_per_m","接触纹理密度 /m",.1,20,.1),("natural_contact_separation_m","接触间隙 m",0,.01,.0005)])]:
    for field,label,lo,hi,step in items:
        add("visual_"+field,"water",label,0,lo,hi,step,target="uniform",node=node,field=field)
for field,label,default,low,high in [("foam_lifetime_s","白沫消散时间 s",1.8,.1,10),("foam_source_gain","白沫生成增益",25,0,100)]:
    add(field,"water",label,default,low,high,.1,"restart","foam")
for field,label in [("sand_dry_color","干沙色"),("sand_wet_color","湿沙色")]:
    add("visual_"+field,"sand",label,[1,1,1,1],target="uniform",kind="color",node="GpuSandTerrain",field=field)
for field,label,lo,hi,step in [("sand_grain_scale","沙粒密度 /m",1,100,1),("sand_grain_gain","沙粒颜色起伏",0,.5,.01),("sand_grain_normal","沙粒法线强度",0,1,.01),("sand_dry_roughness","干沙粗糙度",0,1,.01),("sand_wet_roughness","湿沙粗糙度",0,1,.01),("sand_dry_specular","干沙高光",0,1,.01),("sand_wet_specular","湿沙高光",0,1,.01)]:
    add("visual_"+field,"sand",label,0,lo,hi,step,target="uniform",node="GpuSandTerrain",field=field)
for field,label in [("use_grain","沙粒细节"),("use_grain_normal","沙粒法线"),("use_wet_finish","湿沙表面"),("use_compaction_tint","压实色差")]:
    add("visual_"+field,"sand",label,True,target="uniform",kind="bool",node="GpuSandTerrain",field=field)
add("sand_debug","diagnostics","沙字段显示",0,0,5,1,target="uniform",node="GpuSandTerrain",field="debug_mode",kind="choice",options=["正常","诊断 1","诊断 2","诊断 3","诊断 4","压实"])
for field,label in [("rdc_absorption_rgb","水体 RGB 吸收"),("rdc_transmission_tint","水体透射色"),("rdc_surface_color","水面基色")]:
    # Absorption is a coefficient, not a color picker clamped to [0,1].
    if field=="rdc_absorption_rgb":
        for component in range(3):
            add("visual_absorption_"+str(component),"water",label+" RGB"[component+1],0,0,20,.05,target="uniform_component",node="GpuWaterSurface",field=field,component=component)
    else:
        add("visual_"+field,"water",label,[1,1,1,1],target="uniform",kind="color",node="GpuWaterSurface",field=field)
for field,label,lo,hi,step in [("move_speed_m_s","相机移动 m/s",.1,30,.1),("fast_multiplier","相机加速倍率",1,10,.1),("mouse_sensitivity","转向灵敏度",.0005,.02,.0005),("fov","视场角 °",30,110,1)]:
    add("camera_"+field,"environment",label,0,lo,hi,step,target="property",node="GpuPlayerCamera",field=field)
add("sun_energy","environment","太阳能量",1,0,4,.05,target="sun",field="light_energy")
add("sun_color","environment","太阳颜色",[1,1,1,1],target="sun",field="light_color",kind="color")
add("ambient_energy","environment","环境光能量",.65,0,2,.05,target="ambient",field="ambient_light_energy")
add("ambient_color","environment","环境光颜色",[1,1,1,1],target="ambient",field="ambient_light_color",kind="color")
add("sampling","diagnostics","采集进程帧统计",True,target="sampling",kind="bool")

for name,label in [("bottle","水瓶"),("wood_plank","木板"),("wood_stick","木棍")]:
    for field,title,lo,hi,step in [("mass_kg","质量 kg",.01,100,.01),("friction","摩擦",0,1,.05),
        ("angular_damping","角阻尼",0,5,.05),("drag_time_horizontal_s","水平随流时间 s",.001,5,.01),
        ("drag_time_vertical_s","垂直阻力时间 s",.001,5,.01)]:
        add(name+"_"+field,"props",label+title,0,lo,hi,step,"restart","prop",body=name,field=field)

for field,label,default,lo,hi,step in [
    ("foam_detail_scale_per_m","泡沫纹样密度",1.0,0.5,12.0,0.1),
    ("foam_hole_strength","泡沫破碎程度",1.0,0.0,1.0,0.05),
    ("foam_flow_cycle_s","泡沫流动周期",4.0,0.5,8.0,0.5)]:
    add("visual_"+field,"water",label,default,lo,hi,step,target="uniform",node="GpuWaterSurface",field=field)

def quote(value):
    return json.dumps(value,ensure_ascii=False)


def build(check=False):

    def emit(path, content):
        if check:
            assert path.read_text(encoding="utf-8")==content, "stale parameter artifact: "+str(path)
        else:
            path.write_text(content,encoding="utf-8")

    out=ROOT/"scenes/parameters";out.mkdir(parents=True,exist_ok=True)
    (ROOT/"assets/parameters").mkdir(parents=True,exist_ok=True)
    emit(ROOT/"assets/parameters/catalog.json",json.dumps(ROWS,ensure_ascii=False,indent=2)+"\n")
    titles={"tools":"工具参数","water":"水参数","sand":"沙参数","props":"道具参数","environment":"环境与显示","diagnostics":"性能与诊断"}
    text=['[gd_scene format=3]', '[ext_resource type="Script" path="res://scripts/parameters/parameter_service.gd" id="1"]',
          '[ext_resource type="Script" path="res://scripts/parameters/parameter_row.gd" id="2"]',
          '[node name="Parameters" type="Node"]\nscript = ExtResource("1")']
    for i,(group,title) in enumerate(titles.items()):
        text += [f'[node name="{group}" type="Window" parent="."]\ntitle = "{title}"\nsize = Vector2i(780, 660)\nmin_size = Vector2i(640, 360)\nvisible = false\nforce_native = true\ntransient = false',
            f'[node name="Margin" type="MarginContainer" parent="{group}"]\nanchors_preset = 15\nanchor_right = 1.0\nanchor_bottom = 1.0\noffset_left = 12.0\noffset_top = 12.0\noffset_right = -12.0\noffset_bottom = -12.0',
            f'[node name="Rows" type="VBoxContainer" parent="{group}/Margin"]\nlayout_mode = 2',
            f'[node name="Scene" type="Label" parent="{group}/Margin/Rows"]\nlayout_mode = 2\ntext = "等待场景"',
            f'[node name="Actions" type="HBoxContainer" parent="{group}/Margin/Rows"]\nlayout_mode = 2']
        for name,label in [("Save","保存参数（下次启动沿用）"),("Load","加载已保存参数"),("Reset","恢复默认")]:
            text += [f'[node name="{name}" type="Button" parent="{group}/Margin/Rows/Actions"]\nlayout_mode = 2\ntext = "{label}"\nfocus_mode = 0']
        text += [f'[node name="Message" type="Label" parent="{group}/Margin/Rows"]\nlayout_mode = 2\nautowrap_mode = 3\ntext = "修改仅用于本次运行；需要沿用时请保存。"',
            f'[node name="Scroll" type="ScrollContainer" parent="{group}/Margin/Rows"]\nlayout_mode = 2\nsize_flags_vertical = 3\nhorizontal_scroll_mode = 0',
            f'[node name="Fields" type="VBoxContainer" parent="{group}/Margin/Rows/Scroll"]\nlayout_mode = 2\nsize_flags_horizontal = 3']
        parent=f'{group}/Margin/Rows/Scroll/Fields'
        for row in [r for r in ROWS if r['group']==group]:
            id=row['id'];path=f'{parent}/{id}'
            text += [f'[node name="{id}" type="VBoxContainer" parent="{parent}"]\nlayout_mode = 2\nscript = ExtResource("2")\nparameter_id = "{id}"',
                f'[node name="Line" type="HBoxContainer" parent="{path}"]\nlayout_mode = 2',
                f'[node name="Label" type="Label" parent="{path}/Line"]\nlayout_mode = 2\ncustom_minimum_size = Vector2(300, 0)\ntext = {quote(row["label"])}']
            kind=row['kind'];cls={"bool":"CheckBox","choice":"OptionButton","color":"ColorPickerButton"}.get(kind,"SpinBox")
            props=f'layout_mode = 2\nsize_flags_horizontal = 3'
            if cls=="SpinBox":props+=f'\nmin_value = {row["min"]}\nmax_value = {row["max"]}\nstep = {row["step"]}\nallow_greater = false\nallow_lesser = false'
            if kind=="color":props+='\nedit_alpha = false'
            if kind=="choice":
                props+=f'\nitem_count = {len(row["options"])}'
                for index,label in enumerate(row['options']):props+=f'\npopup/item_{index}/text = {quote(label)}\npopup/item_{index}/id = {index}'
            text += [f'[node name="Value" type="{cls}" parent="{path}/Line"]\n{props}',
                f'[node name="Status" type="Label" parent="{path}"]\nlayout_mode = 2\nautowrap_mode = 3\ntheme_override_font_sizes/font_size = 12']
        if group=="diagnostics":
            text += [f'[node name="Statistics" type="Label" parent="{parent}"]\nlayout_mode = 2\nautowrap_mode = 3\ntext = "等待统计"']
    text += ['[connection signal="changed" from="." to="." method="_refresh_headers"]']
    for group in titles:
        text += [f'[connection signal="close_requested" from="{group}" to="." method="_close_group" binds=["{group}"]]',
                 f'[connection signal="size_changed" from="{group}" to="." method="_layout_changed"]']
        for name,method in [("Save","save_parameters"),("Load","load_parameters"),("Reset","reset_defaults")]:
            suffix=f' binds=["{group}"]' if name=="Reset" else ""
            text += [f'[connection signal="pressed" from="{group}/Margin/Rows/Actions/{name}" to="." method="{method}"{suffix}]']
        for row in [r for r in ROWS if r['group']==group]:
            path=f'{group}/Margin/Rows/Scroll/Fields/{row["id"]}'
            signal={"bool":"toggled","choice":"item_selected","color":"color_changed"}.get(row['kind'],"value_changed")
            method="_color_changed" if row['kind']=="color" else "_changed"
            text += [f'[connection signal="{signal}" from="{path}/Line/Value" to="{path}" method="{method}"]']
    emit(out/"parameter_windows.tscn","\n\n".join(text)+"\n")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true")
    build(parser.parse_args().check)
