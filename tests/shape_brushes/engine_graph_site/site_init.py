"""Capture structured build commands during an explicitly requested SCons dry run."""
import json
import os
from pathlib import Path

import SCons.Platform
import SCons.Script
import SCons.Subst


_original_call = SCons.Platform.TempFileMunge.__call__


def capture_command(self, target, source, env, for_signature):
    destination = os.environ.get('SANDCASTLE_GRAPH_COMMANDS')
    if destination and not for_signature:
        if not SCons.Script.GetOption('no_exec'):
            raise RuntimeError('Engine command capture is restricted to --dry-run')
        name = str(target[0] if isinstance(target, (list, tuple)) else target).replace('\\', '/')
        if name.endswith(('/rendering_device.windows.editor.dev.x86_64.obj', '/servers.windows.editor.dev.x86_64.lib', '/godot.windows.editor.dev.x86_64.exe')):
            args = env.subst_list(self.cmd, SCons.Subst.SUBST_CMD, target, source)[0]
            with Path(destination).open('a', encoding='utf-8') as stream:
                stream.write(json.dumps({'target': name, 'args': [str(arg) for arg in args]}) + '\n')
    return _original_call(self, target, source, env, for_signature)


SCons.Platform.TempFileMunge.__call__ = capture_command
