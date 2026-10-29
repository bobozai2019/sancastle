"""Build an isolated paired graph diagnosis from cached Godot objects, never in place."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

import pickle
import SCons.dblite


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--commands', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--serial-barrier-pair', action='store_true', help='Keep reorder=0 and vary only full barriers; report actual mode once in both engines')
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if output.exists():
        raise RuntimeError('Use a fresh output directory; do not replace an existing pair')
    if source == output or source in output.parents:
        raise RuntimeError('Output must be outside the original engine tree')
    output.mkdir(parents=True)
    (output / 'build_engine_graph_pair.executed.py').write_bytes(Path(__file__).read_bytes())
    captured = [json.loads(line) for line in args.commands.read_text(encoding='utf-8').splitlines()]
    compile_row = next(r for r in captured if r['target'].endswith('/rendering_device.windows.editor.dev.x86_64.obj'))
    link_row = next(r for r in captured if r['target'].endswith('/godot.windows.editor.dev.x86_64.exe'))
    cache = SCons.dblite.open(str(source / '.sconsign5.dblite'), 'r')
    link_info = pickle.loads(cache['bin'])['godot.windows.editor.dev.x86_64.exe'].binfo
    device_key = next(k for k in cache.keys() if str(k).replace('\\', '/') == 'bin/obj/servers/rendering')
    device_info = pickle.loads(cache[device_key])['rendering_device.windows.editor.dev.x86_64.obj'].binfo
    cached_inputs = []
    for name, info in list(zip(device_info.bimplicit, device_info.bimplicitsigs)) + list(zip(device_info.bsources, device_info.bsourcesigs)) + list(zip(link_info.bsources, link_info.bsourcesigs)) + list(zip(link_info.bimplicit, link_info.bimplicitsigs)):
        path = source / name
        # The retired compiler/linker paths are metadata, not relink inputs.
        if str(name).lower().endswith(('.exe', '.dll')):
            continue
        expected = getattr(info, 'csig', None)
        actual = hashlib.md5(path.read_bytes()).hexdigest() if path.is_file() else None
        if expected != actual:
            raise RuntimeError('Cached input mismatch: ' + str(path))
        cached_inputs.append({'path': str(path), 'cached_md5': expected, 'actual_md5': actual})
    # The cached editor was built with tests=yes. Current SCons defaults omit
    # that archive, although cached main/GDScript objects still require it.
    known = {a.replace('\\', '/') for a in link_row['args']}
    missing_cached_libraries = [name for name in link_info.bimplicit if str(name).endswith('.lib') and (source / name).is_file() and name.replace('\\', '/') not in known]
    link_row['args'].extend(missing_cached_libraries)
    # Preserve the cached successful target's archive order, including tests
    # immediately after main. Appending it after scene changes MSVC extraction.
    cached_libraries = [name for name in link_info.bimplicit if str(name).endswith('.lib') and (source / name).is_file()]
    library_names = {name.replace('\\', '/') for name in cached_libraries}
    ordered_args = []
    inserted = False
    for arg in link_row['args']:
        if arg.replace('\\', '/') in library_names:
            if not inserted:
                ordered_args.extend(cached_libraries)
                inserted = True
        else:
            ordered_args.append(arg)
    link_row['args'] = ordered_args
    build_env = json.loads((source / '.scons_env.json').read_text())['ENV']
    env = os.environ.copy()
    for name in ['PATH', 'INCLUDE', 'LIB', 'LIBPATH']:
        env[name] = str(build_env[name])
    tools = {name: shutil.which(name + '.exe', path=env['PATH']) for name in ['cl', 'lib', 'link']}
    if not all(tools.values()):
        raise RuntimeError('The captured MSVC environment is unavailable')
    device_source = source / 'servers/rendering/rendering_device.cpp'
    device_object = source / compile_row['target']
    servers = source / 'bin/obj/servers/servers.windows.editor.dev.x86_64.lib'
    original_paths = [device_source, device_object, servers, source / 'bin/godot.windows.editor.dev.x86_64.exe', source / 'bin/godot.windows.editor.dev.x86_64.console.exe']
    # Link arguments identify every cached object/library consumed by this pair.
    for arg in link_row['args'][1:]:
        path = source / arg
        if not arg.startswith('/') and path.is_file():
            original_paths.append(path)
    originals = {str(p): sha(p) for p in set(original_paths)}
    text = device_source.read_text(encoding='utf-8')
    if text.count('#define RENDER_GRAPH_REORDER 1') != 1 or text.count('#define RENDER_GRAPH_FULL_BARRIERS 0') != 1:
        raise RuntimeError('Unexpected graph source; do not apply a speculative replacement')
    evidence = {'status': 'building', 'scope': 'Paired cached-object relink; both recompile rendering_device.cpp with one current compiler. Source cache inputs and actual tools are indexed. This does not establish complete source provenance or equivalence to any earlier engine binary.', 'source': str(source), 'originals': originals, 'cached_inputs': cached_inputs, 'cached_library_order': cached_libraries, 'added_cached_libraries': missing_cached_libraries, 'builder_sha256': sha(__file__), 'captured_commands_sha256': sha(args.commands), 'tools': {k: {'path': v, 'sha256': sha(v)} for k, v in tools.items()}, 'variants': {}, 'commands': []}

    def save():
        (output / 'build_manifest.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')

    def run(name, program, argv, directory):
        rsp = directory / (name + '.rsp')
        rsp.write_text(subprocess.list2cmdline(argv) + '\n', encoding='utf-8')
        evidence['commands'].append({'name': name, 'program': program, 'arguments_file': str(rsp), 'arguments_sha256': sha(rsp), 'working_directory': str(source)})
        save()
        with (directory / (name + '.log')).open('wb') as log:
            process = subprocess.run([program, '@' + str(rsp)], cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        if process.returncode:
            raise RuntimeError(name + ' failed: ' + str(process.returncode))

    try:
        variants = [('serial_barriers_off', 0, 0), ('serial_barriers_on', 0, 1)] if args.serial_barrier_pair else [('baseline', 1, 0), ('serial_graph', 0, 0)]
        for mode, reorder, full_barriers in variants:
            directory = output / mode
            directory.mkdir()
            cloned_source = directory / 'rendering_device.cpp'
            variant_text=text.replace('#define RENDER_GRAPH_REORDER 1', '#define RENDER_GRAPH_REORDER ' + str(reorder)).replace('#define RENDER_GRAPH_FULL_BARRIERS 0', '#define RENDER_GRAPH_FULL_BARRIERS ' + str(full_barriers))
            if args.serial_barrier_pair:
                marker='\tdraw_graph.end(RENDER_GRAPH_REORDER == 1, RENDER_GRAPH_FULL_BARRIERS == 1, command_buffer, frames[frame].command_buffer_pool);'
                if variant_text.count(marker)!=1:
                    raise RuntimeError('Unexpected graph submission site')
                report='\tstatic bool sandcastle_graph_reported = false;\n\tif (!sandcastle_graph_reported) {\n\t\tprint_line(vformat("SANDCASTLE_GRAPH_MODE reorder=%d full=%d honors=%d", RENDER_GRAPH_REORDER, RENDER_GRAPH_FULL_BARRIERS, int(driver->api_trait_get(RDD::API_TRAIT_HONORS_PIPELINE_BARRIERS))));\n\t\tsandcastle_graph_reported = true;\n\t}\n'
                variant_text=variant_text.replace(marker,report+marker)
            cloned_source.write_text(variant_text, encoding='utf-8')
            obj = directory / device_object.name
            compile_args = []
            for arg in compile_row['args'][1:]:
                if arg.lower().startswith('/fo'):
                    compile_args.append('/Fo' + str(obj))
                elif arg.replace('\\', '/') == 'servers/rendering/rendering_device.cpp':
                    compile_args.append(str(cloned_source))
                elif not arg.lower().startswith('/fd'):
                    compile_args.append(arg)
            compile_args.extend(['/I' + str(device_source.parent), '/Fd' + str(directory / 'compile.pdb')])
            run('compile_device', tools['cl'], compile_args, directory)
            trimmed = directory / 'servers_without_device.lib'
            patched = directory / servers.name
            member = compile_row['target'].replace('/', '\\')
            run('remove_old_device', tools['lib'], ['/nologo', '/OUT:' + str(trimmed), '/REMOVE:' + member, str(servers)], directory)
            run('insert_device', tools['lib'], ['/nologo', '/OUT:' + str(patched), str(trimmed), str(obj)], directory)
            member_list = subprocess.check_output([tools['lib'], '/nologo', '/LIST', str(patched)], cwd=source, env=env, text=True)
            (directory / 'archive_members.txt').write_text(member_list, encoding='utf-8')
            members = [line for line in member_list.splitlines() if line.replace('\\', '/').endswith('/' + obj.name) or line == obj.name]
            if len(members) != 1:
                raise RuntimeError('Archive must contain exactly one rendering_device object: ' + str(members))
            executable = directory / 'godot.windows.editor.dev.x86_64.exe'
            link_args = []
            replaced = 0
            for arg in link_row['args'][1:]:
                lower = arg.lower()
                if lower.startswith('/out:'):
                    link_args.append('/OUT:' + str(executable))
                elif lower.startswith(('/pdb:', '/implib:')):
                    prefix = arg.split(':', 1)[0]
                    extension = '.pdb' if lower.startswith('/pdb:') else '.lib'
                    link_args.append(prefix + ':' + str(directory / ('godot' + extension)))
                elif arg.replace('\\', '/') == 'bin/obj/servers/servers.windows.editor.dev.x86_64.lib':
                    link_args.append(str(patched)); replaced += 1
                else:
                    link_args.append(arg)
            if replaced != 1:
                raise RuntimeError('Expected exactly one original servers archive in link inputs')
            run('link_engine', tools['link'], link_args, directory)
            runtime_files = []
            for name in ['godot.windows.editor.dev.x86_64.console.exe', 'D3D12Core.dll', 'd3d12SDKLayers.dll']:
                destination = directory / name
                shutil.copy2(source / 'bin' / name, destination)
                runtime_files.append({'path': str(destination), 'sha256': sha(destination)})
            evidence['variants'][mode] = {'render_graph_reorder': reorder, 'render_graph_full_barriers': full_barriers, 'mode_report_enabled': args.serial_barrier_pair, 'source_sha256': sha(cloned_source), 'object_sha256': sha(obj), 'archive_sha256': sha(patched), 'engine': str(executable), 'engine_sha256': sha(executable), 'runtime_files': runtime_files}
            save()
        evidence['status'] = 'built_not_runtime_verified'
    except Exception as error:
        evidence['status'] = 'failed'
        evidence['error'] = str(error)
        raise
    finally:
        evidence['original_mismatches'] = [p for p, expected in originals.items() if sha(p) != expected]
        save()
        if evidence['original_mismatches']:
            raise RuntimeError('Original input identity changed during build')
    print('ENGINE_GRAPH_PAIR_BUILT', str(output))


if __name__ == '__main__':
    main()
