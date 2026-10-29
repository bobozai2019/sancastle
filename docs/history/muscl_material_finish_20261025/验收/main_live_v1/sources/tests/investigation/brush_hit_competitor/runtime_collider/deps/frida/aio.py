from . import _frida
import asyncio
import contextvars
import time
import dataclasses
import fnmatch
import functools
import inspect
import json
import sys
import traceback
from typing import (Any, Callable, Dict, List, Literal, Mapping, Optional, Tuple, Sequence, Union, TypeVar, cast,
                    overload)

if sys.version_info >= (3, 11):
    from typing import NotRequired, ParamSpec, TypedDict
else:
    from typing_extensions import NotRequired, ParamSpec, TypedDict


ServerNotRunningError = _frida.ServerNotRunningError
ExecutableNotFoundError = _frida.ExecutableNotFoundError
ExecutableNotSupportedError = _frida.ExecutableNotSupportedError
ProcessNotFoundError = _frida.ProcessNotFoundError
ProcessNotRespondingError = _frida.ProcessNotRespondingError
InvalidArgumentError = _frida.InvalidArgumentError
InvalidOperationError = _frida.InvalidOperationError
PermissionDeniedError = _frida.PermissionDeniedError
AddressInUseError = _frida.AddressInUseError
TimedOutError = _frida.TimedOutError
NotSupportedError = _frida.NotSupportedError
ProtocolError = _frida.ProtocolError
TransportError = _frida.TransportError
OperationCancelledError = _frida.OperationCancelledError

ProcessTarget = Union[int, str]


class ScriptErrorMessage(TypedDict):
    type: Literal["error"]
    description: str
    stack: NotRequired[str]
    fileName: NotRequired[str]
    lineNumber: NotRequired[int]
    columnNumber: NotRequired[int]


class ScriptPayloadMessage(TypedDict):
    type: Literal["send"]
    payload: NotRequired[Any]


ScriptMessage = Union[ScriptPayloadMessage, ScriptErrorMessage]
ScriptMessageCallback = Callable[[ScriptMessage, Optional[bytes]], None]
ScriptDestroyedCallback = Callable[[], None]

SessionDetachedCallback = Callable[
    [
        Literal[
            "application-requested", "process-replaced", "process-terminated", "connection-terminated", "device-lost"
        ],
        Optional[_frida.Crash],
    ],
    None,
]

BusDetachedCallback = Callable[[], None]
BusMessageCallback = Callable[[Mapping[Any, Any], Optional[bytes]], None]

ServiceCloseCallback = Callable[[], None]
ServiceMessageCallback = Callable[[Any], None]

DeviceSpawnAddedCallback = Callable[[_frida.Spawn], None]
DeviceSpawnRemovedCallback = Callable[[_frida.Spawn], None]
DeviceChildAddedCallback = Callable[[_frida.Child], None]
DeviceChildRemovedCallback = Callable[[_frida.Child], None]
DeviceProcessCrashedCallback = Callable[[_frida.Crash], None]
DeviceOutputCallback = Callable[[int, int, bytes], None]
DeviceUninjectedCallback = Callable[[int], None]
DeviceLostCallback = Callable[[], None]

DeviceManagerAddedCallback = Callable[[_frida.Device], None]
DeviceManagerRemovedCallback = Callable[[_frida.Device], None]
DeviceManagerChangedCallback = Callable[[], None]

PortalServiceNodeJoinedCallback = Callable[[int, _frida.Application], None]
PortalServiceNodeLeftCallback = Callable[[int, _frida.Application], None]
PortalServiceNodeConnectedCallback = Callable[[int, Tuple[str, int]], None]
PortalServiceNodeDisconnectedCallback = Callable[[int, Tuple[str, int]], None]
PortalServiceControllerConnectedCallback = Callable[[int, Tuple[str, int]], None]
PortalServiceControllerDisconnectedCallback = Callable[[int, Tuple[str, int]], None]
PortalServiceAuthenticatedCallback = Callable[[int, Mapping[Any, Any]], None]
PortalServiceSubscribeCallback = Callable[[int], None]
PortalServiceMessageCallback = Callable[[int, Mapping[Any, Any], Optional[bytes]], None]


class CompilerDiagnosticFile(TypedDict):
    path: str
    line: int
    character: int


class CompilerDiagnostic(TypedDict):
    category: str
    code: int
    file: NotRequired[CompilerDiagnosticFile]
    text: str


CompilerStartingCallback = Callable[[], None]
CompilerFinishedCallback = Callable[[], None]
CompilerOutputCallback = Callable[[str], None]
CompilerDiagnosticsCallback = Callable[[List[CompilerDiagnostic]], None]

CompilerOutputFormat = Literal["unescaped", "hex-bytes", "c-string"]
CompilerBundleFormat = Literal["esm", "iife"]
CompilerTypeCheck = Literal["full", "none"]
CompilerSourceMaps = Literal["included", "omitted"]
CompilerCompression = Literal["none", "terser"]
CompilerPlatform = Literal["neutral", "gum", "browser"]

PackageManagerInstallProgressCallback = Callable[
    [
        Literal[
            "initializing",
            "preparing-dependencies",
            "resolving-package",
            "fetching-resource",
            "package-already-installed",
            "downloading-package",
            "package-installed",
            "resolving-and-installing-all",
            "complete",
        ],
        float,
        Optional[str],
    ],
    None,
]

PackageRole = Literal["runtime", "development", "optional", "peer"]


_to_json = json.dumps


def _wrap(impl):
    if impl is None:
        return None
    cls = _WRAPPERS.get(type(impl).__name__)
    if cls is None:
        return impl
    wrapper = cls.__new__(cls)
    wrapper._impl = impl
    setup = getattr(wrapper, "_setup", None)
    if setup is not None:
        setup()
    return wrapper


def _unwrap(obj):
    if obj is None:
        return None
    return getattr(obj, "_impl", obj)


def _make_signal_handler(callback):
    def handler(*args):
        return callback(*[_wrap(arg) for arg in args])

    handler._frida_original = callback
    handler.__signature__ = inspect.signature(callback)
    return handler


def _to_envp(value):
    if isinstance(value, dict):
        return [f"{key}={val}" for key, val in value.items()]
    return value


def _make_options(cls, values, selectors):
    options = cls()
    _apply_settings(options, values, selectors)
    return options


def _apply_settings(impl, values, selectors):
    for name, value in values.items():
        if value is None:
            continue
        select = selectors.get(name)
        if select is None:
            setattr(impl, name, _unwrap(value))
        elif isinstance(value, dict):
            add = getattr(impl, select)
            for key, element in value.items():
                add(key, _unwrap(element))
        else:
            add = getattr(impl, select)
            for element in value:
                add(_unwrap(element))


_current_cancellable: contextvars.ContextVar = contextvars.ContextVar("frida_current_cancellable", default=None)


def _dispatch(loop, callback, *args):
    try:
        loop.call_soon_threadsafe(callback, *args)
    except RuntimeError:
        pass


async def _invoke(method, args):
    loop = asyncio.get_running_loop()
    future = loop.create_future()
    ambient = _current_cancellable.get()
    cancellable = ambient._impl if ambient is not None else _frida.Cancellable()

    def deliver(result, error):
        if future.done():
            return
        if error is not None:
            future.set_exception(error)
        else:
            future.set_result(result)

    def on_complete(result, error):
        _dispatch(loop, deliver, result, error)

    method(*args, on_complete, cancellable)

    try:
        return await future
    except asyncio.CancelledError:
        cancellable.cancel()
        raise


class _Implementation:
    _loop: Any

    def _frida_dispatch(self, name: str, args: List[Any], completion: Any) -> None:
        loop = self._loop

        async def run() -> None:
            try:
                result = getattr(self, name)(*[_wrap(a) for a in args])
                if asyncio.iscoroutine(result):
                    result = await result
                result = _unwrap(result)
                error = None
            except Exception as e:
                result = None
                error = e
            _frida._complete_request(completion, result, error)

        _dispatch(loop, lambda: loop.create_task(run()))


__version__ = _frida.__version__


def get_device_manager() -> "DeviceManager":
    return _wrap(_frida.get_device_manager())


async def get_device(id: str, timeout: Union[int, float] = 0) -> "Device":
    return await get_device_manager().get_device_by_id(id, int(timeout * 1000))


async def get_device_matching(predicate: Callable[["Device"], bool], timeout: Union[int, float] = 0) -> "Device":
    return await get_device_manager().get_device_matching(predicate, timeout)


async def get_local_device() -> "Device":
    return await get_device_manager().get_device_by_type("local", 0)


async def get_remote_device() -> "Device":
    return await get_device_manager().get_device_by_type("remote", 0)


async def get_usb_device(timeout: Union[int, float] = 0) -> "Device":
    return await get_device_manager().get_device_by_type("usb", int(timeout * 1000))


async def enumerate_devices() -> List["Device"]:
    return await get_device_manager().enumerate_devices()


async def query_system_parameters() -> Dict[str, Any]:
    return await (await get_local_device()).query_system_parameters()


async def spawn(
    program: Union[str, List[Union[str, bytes]]],
    argv: Optional[List[Union[str, bytes]]] = None,
    envp: Optional[Dict[str, str]] = None,
    env: Optional[Dict[str, str]] = None,
    cwd: Optional[str] = None,
    stdio: Optional[str] = None,
    **aux: Any,
) -> int:
    device = await get_local_device()
    return await device.spawn(
        program, argv=argv, envp=envp, env=env, cwd=cwd, stdio=stdio, **aux
    )


async def resume(target: ProcessTarget) -> None:
    return await (await get_local_device()).resume(target)


async def kill(target: ProcessTarget) -> None:
    return await (await get_local_device()).kill(target)


async def attach(target: ProcessTarget, **kwargs: Any) -> "Session":
    return await (await get_local_device()).attach(target, **kwargs)


async def inject_library_file(target: ProcessTarget, path: str, entrypoint: str, data: str) -> int:
    return await (await get_local_device()).inject_library_file(target, path, entrypoint, data)


async def inject_library_blob(target: ProcessTarget, blob: bytes, entrypoint: str, data: str) -> int:
    return await (await get_local_device()).inject_library_blob(target, blob, entrypoint, data)


async def shutdown() -> None:
    await get_device_manager().close()


def make_auth_callback(callback: Callable[[str], Any]) -> Callable[[Any], str]:
    def authenticate(token: str) -> str:
        session_info = callback(token)
        return json.dumps(session_info)

    return authenticate


def _to_camel_case(name: str) -> str:
    result = ""
    capitalize = False
    for ch in name:
        if ch == "_":
            capitalize = True
        elif capitalize:
            result += ch.upper()
            capitalize = False
        else:
            result += ch
    return result


class RPCException(Exception):
    def __str__(self) -> str:
        return str(self.args[2]) if len(self.args) >= 3 else str(self.args[0])


class _ScriptExports:
    def __init__(self, script: "Script") -> None:
        self._script = script

    def __getattr__(self, name: str) -> Callable[..., Any]:
        script = self._script
        js_name = _to_camel_case(name)

        def method(*args: Any) -> Any:
            if args and isinstance(args[-1], bytes):
                params, data = list(args[:-1]), args[-1]
            else:
                params, data = list(args), None
            return script._rpc_request(["call", js_name, params], data)

        return method


ScriptExportsAsync = _ScriptExports


@dataclasses.dataclass
class RPCResult:
    finished: bool = False
    value: Any = None
    error: Optional[Exception] = None


def make_rpc_call_request(js_name: str, args: Sequence[Any]) -> Tuple[List[Any], Optional[bytes]]:
    if args and isinstance(args[-1], bytes):
        raw_args = args[:-1]
        data = args[-1]
    else:
        raw_args = args
        data = None
    return (["call", js_name, raw_args], data)


class CancellablePollFD:
    def __init__(self, cancellable: _frida.Cancellable) -> None:
        self.handle = cancellable.get_fd()
        self._cancellable: Optional[_frida.Cancellable] = cancellable

    def __del__(self) -> None:
        self.release()

    def release(self) -> None:
        if self._cancellable is not None:
            if self.handle != -1:
                self._cancellable.release_fd()
                self.handle = -1
            self._cancellable = None

    def __repr__(self) -> str:
        return repr(self.handle)

    def __enter__(self) -> int:
        return self.handle

    def __exit__(self, *exc: Any) -> None:
        self.release()


P = ParamSpec("P")
R = TypeVar("R", covariant=True)


def cancellable(f: Callable[P, R]) -> Callable[P, R]:
    @functools.wraps(f)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        cancellable = kwargs.pop("cancellable", None)
        if cancellable is not None:
            with cast(Cancellable, cancellable):
                return f(*args, **kwargs)

        return f(*args, **kwargs)

    return wrapper


class GObject:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.GObject(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def notify(self, property_name: str) -> None:
        return self._impl.notify(property_name)


class DeviceManager:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.DeviceManager(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'remote_devices': 'add_remote_device', 'barebone_devices': 'add_barebone_device'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @overload
    def on(self, signal: Literal["added"], callback: DeviceManagerAddedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["removed"], callback: DeviceManagerRemovedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["changed"], callback: DeviceManagerChangedCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["added"], callback: DeviceManagerAddedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["removed"], callback: DeviceManagerRemovedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["changed"], callback: DeviceManagerChangedCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    async def close(self) -> None:
        return await _invoke(self._impl.close, ())

    async def get_device_by_id(self, id: str, timeout: int) -> "Device":
        return _wrap(await _invoke(self._impl.get_device_by_id, (id, timeout, )))

    async def get_device_by_type(self, type: str, timeout: int) -> "Device":
        return _wrap(await _invoke(self._impl.get_device_by_type, (type, timeout, )))

    async def find_device_by_id(self, id: str, timeout: int) -> "Device":
        return _wrap(await _invoke(self._impl.find_device_by_id, (id, timeout, )))

    async def find_device_by_type(self, type: str, timeout: int) -> "Device":
        return _wrap(await _invoke(self._impl.find_device_by_type, (type, timeout, )))

    async def enumerate_devices(self) -> list["Device"]:
        return [_wrap(element) for element in await _invoke(self._impl.enumerate_devices, ())]

    async def add_remote_device(self, address: str, **kwargs) -> "Device":
        return _wrap(await _invoke(self._impl.add_remote_device, (address, _make_options(_frida.RemoteDeviceOptions, kwargs, {}), )))

    async def remove_remote_device(self, address: str) -> None:
        return await _invoke(self._impl.remove_remote_device, (address, ))

    async def add_barebone_device(self, config: Optional["BareboneConfig"] = None, **kwargs) -> "Device":
        return _wrap(await _invoke(self._impl.add_barebone_device, (_unwrap(config), _make_options(_frida.BareboneDeviceOptions, kwargs, {}), )))

    async def remove_barebone_device(self, device: Optional["Device"] = None) -> None:
        return await _invoke(self._impl.remove_barebone_device, (_unwrap(device), ))

    async def get_device_matching(self, predicate: Callable[["Device"], bool], timeout: Union[int, float] = 0) -> "Device":
        deadline = time.monotonic() + timeout
        while True:
            for device in await self.enumerate_devices():
                if predicate(device):
                    return device
            if time.monotonic() >= deadline:
                raise _frida.InvalidArgumentError("no matching device found")
            await asyncio.sleep(0.05)


    async def get_device(self, id: Optional[str], timeout: Union[int, float] = 0) -> "Device":
        return await self.get_device_matching(lambda d: d.id == id, timeout)


    async def get_local_device(self) -> "Device":
        return await self.get_device_matching(lambda d: d.type == "local", 0)


    async def get_remote_device(self) -> "Device":
        return await self.get_device_matching(lambda d: d.type == "remote", 0)


    async def get_usb_device(self, timeout: Union[int, float] = 0) -> "Device":
        return await self.get_device_matching(lambda d: d.type == "usb", timeout)


class Device:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Device(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @overload
    def on(self, signal: Literal["spawn-added"], callback: DeviceSpawnAddedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["spawn-removed"], callback: DeviceSpawnRemovedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["child-added"], callback: DeviceChildAddedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["child-removed"], callback: DeviceChildRemovedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["process-crashed"], callback: DeviceProcessCrashedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["output"], callback: DeviceOutputCallback) -> None: ...
    @overload
    def on(self, signal: Literal["uninjected"], callback: DeviceUninjectedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["lost"], callback: DeviceLostCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["spawn-added"], callback: DeviceSpawnAddedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["spawn-removed"], callback: DeviceSpawnRemovedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["child-added"], callback: DeviceChildAddedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["child-removed"], callback: DeviceChildRemovedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["process-crashed"], callback: DeviceProcessCrashedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["output"], callback: DeviceOutputCallback) -> None: ...
    @overload
    def off(self, signal: Literal["uninjected"], callback: DeviceUninjectedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["lost"], callback: DeviceLostCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    @property
    def is_lost(self) -> bool:
        return self._impl.is_lost()

    def override_option(self, name: str, val: Any) -> None:
        return self._impl.override_option(name, val)

    async def query_system_parameters(self) -> dict:
        return await _invoke(self._impl.query_system_parameters, ())

    async def get_frontmost_application(self, **kwargs) -> "Application":
        return _wrap(await _invoke(self._impl.get_frontmost_application, (_make_options(_frida.FrontmostQueryOptions, kwargs, {}), )))

    async def enumerate_applications(self, **kwargs) -> list["Application"]:
        return [_wrap(element) for element in await _invoke(self._impl.enumerate_applications, (_make_options(_frida.ApplicationQueryOptions, kwargs, {'identifiers': 'select_identifier'}), ))]

    async def get_process_by_pid(self, pid: int, **kwargs) -> "Process":
        return _wrap(await _invoke(self._impl.get_process_by_pid, (pid, _make_options(_frida.ProcessMatchOptions, kwargs, {}), )))

    async def get_process_by_name(self, name: str, **kwargs) -> "Process":
        return _wrap(await _invoke(self._impl.get_process_by_name, (name, _make_options(_frida.ProcessMatchOptions, kwargs, {}), )))

    async def find_process_by_pid(self, pid: int, **kwargs) -> "Process":
        return _wrap(await _invoke(self._impl.find_process_by_pid, (pid, _make_options(_frida.ProcessMatchOptions, kwargs, {}), )))

    async def find_process_by_name(self, name: str, **kwargs) -> "Process":
        return _wrap(await _invoke(self._impl.find_process_by_name, (name, _make_options(_frida.ProcessMatchOptions, kwargs, {}), )))

    async def enumerate_processes(self, **kwargs) -> list["Process"]:
        return [_wrap(element) for element in await _invoke(self._impl.enumerate_processes, (_make_options(_frida.ProcessQueryOptions, kwargs, {'pids': 'select_pid'}), ))]

    async def enable_spawn_gating(self, **kwargs) -> None:
        return await _invoke(self._impl.enable_spawn_gating, (_make_options(_frida.SpawnGatingOptions, kwargs, {}), ))

    async def disable_spawn_gating(self) -> None:
        return await _invoke(self._impl.disable_spawn_gating, ())

    async def enumerate_pending_spawn(self) -> list["Spawn"]:
        return [_wrap(element) for element in await _invoke(self._impl.enumerate_pending_spawn, ())]

    async def enumerate_pending_children(self) -> list["Child"]:
        return [_wrap(element) for element in await _invoke(self._impl.enumerate_pending_children, ())]

    async def spawn(self, program: Union[str, List[Union[str, bytes]]], argv: Optional[List[Union[str, bytes]]] = None, envp: Optional[Mapping[str, str]] = None, env: Optional[Mapping[str, str]] = None, cwd: Optional[str] = None, stdio: Optional[str] = None, **aux: Any) -> int:
        if not isinstance(program, str):
            args = list(program)
            argv = args if len(args) > 1 else None
            first = args[0]
            program = first.decode() if isinstance(first, bytes) else first

        options = _frida.SpawnOptions()
        if argv is not None:
            options.argv = [arg.decode() if isinstance(arg, bytes) else arg for arg in argv]
        if envp is not None:
            options.envp = _to_envp(envp)
        if env is not None:
            options.env = _to_envp(env)
        if cwd is not None:
            options.cwd = cwd
        if stdio is not None:
            options.stdio = stdio
        if aux:
            options.aux = aux
        return await _invoke(self._impl.spawn, (program, options, ))

    async def input(self, target: ProcessTarget, data: bytes) -> None:
        pid = await self._pid_of(target)
        return await _invoke(self._impl.input, (pid, data, ))

    async def resume(self, target: ProcessTarget) -> None:
        pid = await self._pid_of(target)
        return await _invoke(self._impl.resume, (pid, ))

    async def kill(self, target: ProcessTarget) -> None:
        pid = await self._pid_of(target)
        return await _invoke(self._impl.kill, (pid, ))

    async def attach(self, target: ProcessTarget, **kwargs: Any) -> "Session":
        pid = await self._pid_of(target)
        return _wrap(await _invoke(self._impl.attach, (pid, _make_options(_frida.SessionOptions, kwargs, {'linker_notifier_offsets': 'add_linker_notifier_offset'}), )))

    async def inject_library_file(self, target: ProcessTarget, path: str, entrypoint: str, data: str) -> int:
        pid = await self._pid_of(target)
        return await _invoke(self._impl.inject_library_file, (pid, path, entrypoint, data, ))

    async def inject_library_blob(self, target: ProcessTarget, blob: bytes, entrypoint: str, data: str) -> int:
        pid = await self._pid_of(target)
        return await _invoke(self._impl.inject_library_blob, (pid, blob, entrypoint, data, ))

    async def open_channel(self, address: str) -> "IOStream":
        return _wrap(await _invoke(self._impl.open_channel, (address, )))

    async def open_service(self, address: str) -> "Service":
        return _wrap(await _invoke(self._impl.open_service, (address, )))

    async def unpair(self) -> None:
        return await _invoke(self._impl.unpair, ())

    @property
    def id(self) -> str:
        return self._impl.id

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def icon(self) -> Any:
        return self._impl.icon

    @property
    def dtype(self) -> str:
        return self._impl.dtype

    @property
    def bus(self) -> "Bus":
        return _wrap(self._impl.bus)

    @property
    def type(self) -> str:
        return self.dtype

    def get_bus(self) -> "Bus":
        return self.bus

    async def get_process(self, process_name: str) -> "Process":
        process_name_lc = process_name.lower()
        matching = [
            process
            for process in await self.enumerate_processes()
            if fnmatch.fnmatchcase(process.name.lower(), process_name_lc)
        ]
        if len(matching) == 1:
            return matching[0]
        if len(matching) > 1:
            matches = ", ".join(f"{p.name} (pid: {p.pid})" for p in matching)
            raise _frida.ProcessNotFoundError(f"ambiguous name; it matches: {matches}")
        raise _frida.ProcessNotFoundError(f"unable to find process with name '{process_name}'")

    async def _pid_of(self, target: ProcessTarget) -> int:
        if isinstance(target, str):
            return (await self.get_process(target)).pid
        return target

    def __repr__(self):
        return f"Device(id={self.id!r}, name={self.name!r}, dtype={self.dtype!r})"


class BareboneConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()

    @property
    def connection(self) -> "BareboneConnectionConfig":
        return _wrap(self._impl.connection)

    @connection.setter
    def connection(self, value: "BareboneConnectionConfig") -> None:
        self._impl.connection = _unwrap(value)

    @property
    def allocator(self) -> "BareboneAllocatorConfig":
        return _wrap(self._impl.allocator)

    @allocator.setter
    def allocator(self, value: "BareboneAllocatorConfig") -> None:
        self._impl.allocator = _unwrap(value)

    @property
    def agent(self) -> "BareboneAgentConfig":
        return _wrap(self._impl.agent)

    @agent.setter
    def agent(self, value: "BareboneAgentConfig") -> None:
        self._impl.agent = _unwrap(value)

    @property
    def image(self) -> "BareboneImageConfig":
        return _wrap(self._impl.image)

    @image.setter
    def image(self, value: "BareboneImageConfig") -> None:
        self._impl.image = _unwrap(value)

    @property
    def kernel(self) -> str:
        return self._impl.kernel

    @kernel.setter
    def kernel(self, value: str) -> None:
        self._impl.kernel = _unwrap(value)

    def __repr__(self):
        return f"BareboneConfig(kernel={self.kernel!r})"


class BareboneConnectionConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneConnectionConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()

    @property
    def host(self) -> str:
        return self._impl.host

    @host.setter
    def host(self, value: str) -> None:
        self._impl.host = _unwrap(value)

    @property
    def port(self) -> int:
        return self._impl.port

    @port.setter
    def port(self, value: int) -> None:
        self._impl.port = _unwrap(value)

    @property
    def pid(self) -> int:
        return self._impl.pid

    @pid.setter
    def pid(self, value: int) -> None:
        self._impl.pid = _unwrap(value)

    @property
    def flavor(self) -> str:
        return self._impl.flavor

    @flavor.setter
    def flavor(self, value: str) -> None:
        self._impl.flavor = _unwrap(value)

    def __repr__(self):
        return f"BareboneConnectionConfig(host={self.host!r}, port={self.port!r}, pid={self.pid!r}, flavor={self.flavor!r})"


class BareboneAllocatorConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneAllocatorConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()


class BareboneInvalidAllocatorConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInvalidAllocatorConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BarebonePhysicalAllocatorConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BarebonePhysicalAllocatorConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def physical_base(self) -> "BareboneMemoryAddress":
        return _wrap(self._impl.physical_base)

    @physical_base.setter
    def physical_base(self, value: "BareboneMemoryAddress") -> None:
        self._impl.physical_base = _unwrap(value)


class BareboneTargetFunctionsAllocatorConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneTargetFunctionsAllocatorConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'alloc_arguments': 'add_alloc_argument', 'free_arguments': 'add_free_argument'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def clear_alloc_arguments(self) -> None:
        return self._impl.clear_alloc_arguments()

    def add_alloc_argument(self, argument: "BareboneCallArgument") -> None:
        return self._impl.add_alloc_argument(_unwrap(argument))

    def clear_free_arguments(self) -> None:
        return self._impl.clear_free_arguments()

    def add_free_argument(self, argument: "BareboneCallArgument") -> None:
        return self._impl.add_free_argument(_unwrap(argument))

    @property
    def alloc_function(self) -> "BareboneMemoryAddress":
        return _wrap(self._impl.alloc_function)

    @alloc_function.setter
    def alloc_function(self, value: "BareboneMemoryAddress") -> None:
        self._impl.alloc_function = _unwrap(value)

    @property
    def free_function(self) -> "BareboneMemoryAddress":
        return _wrap(self._impl.free_function)

    @free_function.setter
    def free_function(self, value: "BareboneMemoryAddress") -> None:
        self._impl.free_function = _unwrap(value)

    @property
    def alloc_flags(self) -> int:
        return self._impl.alloc_flags

    @alloc_flags.setter
    def alloc_flags(self, value: int) -> None:
        self._impl.alloc_flags = _unwrap(value)

    def __repr__(self):
        return f"BareboneTargetFunctionsAllocatorConfig(alloc_flags={self.alloc_flags!r})"


class BareboneCallArgument:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneCallArgument(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def role(self) -> str:
        return self._impl.role

    @property
    def value(self) -> int:
        return self._impl.value

    def __repr__(self):
        return f"BareboneCallArgument(role={self.role!r}, value={self.value!r})"


class BareboneAgentConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneAgentConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()


class BareboneInvalidAgentConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInvalidAgentConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneInjectedAgentConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInjectedAgentConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def image(self) -> bytes:
        return self._impl.image

    @image.setter
    def image(self, value: bytes) -> None:
        self._impl.image = _unwrap(value)

    @property
    def transport(self) -> "BareboneInjectingTransportConfig":
        return _wrap(self._impl.transport)

    @transport.setter
    def transport(self, value: "BareboneInjectingTransportConfig") -> None:
        self._impl.transport = _unwrap(value)


class BareboneResidentAgentConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneResidentAgentConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def transport(self) -> "BareboneResidentTransportConfig":
        return _wrap(self._impl.transport)

    @transport.setter
    def transport(self, value: "BareboneResidentTransportConfig") -> None:
        self._impl.transport = _unwrap(value)


class BareboneTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()


class BareboneInjectingTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInjectingTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneResidentTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneResidentTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneHostlinkTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneHostlinkTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def qmp(self) -> str:
        return self._impl.qmp

    @qmp.setter
    def qmp(self, value: str) -> None:
        self._impl.qmp = _unwrap(value)

    @property
    def bus(self) -> str:
        return self._impl.bus

    @bus.setter
    def bus(self, value: str) -> None:
        self._impl.bus = _unwrap(value)

    @property
    def fabric(self) -> "BareboneHostlinkFabric":
        return _wrap(self._impl.fabric)

    @fabric.setter
    def fabric(self, value: "BareboneHostlinkFabric") -> None:
        self._impl.fabric = _unwrap(value)

    def __repr__(self):
        return f"BareboneHostlinkTransportConfig(qmp={self.qmp!r}, bus={self.bus!r})"


class BareboneHostlinkFabric:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneHostlinkFabric(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneHostlinkEcamFabric:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneHostlinkEcamFabric(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def ecam(self) -> int:
        return self._impl.ecam

    @ecam.setter
    def ecam(self, value: int) -> None:
        self._impl.ecam = _unwrap(value)

    def __repr__(self):
        return f"BareboneHostlinkEcamFabric(ecam={self.ecam!r})"


class BareboneHostlinkPortsFabric:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneHostlinkPortsFabric(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneHostlinkMmioFabric:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneHostlinkMmioFabric(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneVsockTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneVsockTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def socket_path(self) -> str:
        return self._impl.socket_path

    @socket_path.setter
    def socket_path(self, value: str) -> None:
        self._impl.socket_path = _unwrap(value)

    @property
    def port(self) -> int:
        return self._impl.port

    @port.setter
    def port(self, value: int) -> None:
        self._impl.port = _unwrap(value)

    def __repr__(self):
        return f"BareboneVsockTransportConfig(socket_path={self.socket_path!r}, port={self.port!r})"


class BareboneSerialTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneSerialTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def path(self) -> str:
        return self._impl.path

    @path.setter
    def path(self, value: str) -> None:
        self._impl.path = _unwrap(value)

    def __repr__(self):
        return f"BareboneSerialTransportConfig(path={self.path!r})"


class BareboneVsockPipeTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneVsockPipeTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def socket_path(self) -> str:
        return self._impl.socket_path

    @socket_path.setter
    def socket_path(self, value: str) -> None:
        self._impl.socket_path = _unwrap(value)

    def __repr__(self):
        return f"BareboneVsockPipeTransportConfig(socket_path={self.socket_path!r})"


class BareboneGoldfishPipeTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneGoldfishPipeTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def socket_path(self) -> str:
        return self._impl.socket_path

    @socket_path.setter
    def socket_path(self, value: str) -> None:
        self._impl.socket_path = _unwrap(value)

    def __repr__(self):
        return f"BareboneGoldfishPipeTransportConfig(socket_path={self.socket_path!r})"


class BareboneDeviceTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneDeviceTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def path(self) -> str:
        return self._impl.path

    @path.setter
    def path(self, value: str) -> None:
        self._impl.path = _unwrap(value)

    def __repr__(self):
        return f"BareboneDeviceTransportConfig(path={self.path!r})"


class BareboneSocketTransportConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneSocketTransportConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def path(self) -> str:
        return self._impl.path

    @path.setter
    def path(self, value: str) -> None:
        self._impl.path = _unwrap(value)

    def __repr__(self):
        return f"BareboneSocketTransportConfig(path={self.path!r})"


class BareboneImageConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneImageConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'symbols': 'add_symbol'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def clear_symbols(self) -> None:
        return self._impl.clear_symbols()

    def add_symbol(self, name: str, address: int) -> None:
        return self._impl.add_symbol(name, address)

    def check(self) -> None:
        return self._impl.check()

    @property
    def base(self) -> "BareboneMemoryAddress":
        return _wrap(self._impl.base)

    @base.setter
    def base(self, value: "BareboneMemoryAddress") -> None:
        self._impl.base = _unwrap(value)


class BareboneInvalidImageConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInvalidImageConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'symbols': 'add_symbol'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneXnuKernelcacheConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneXnuKernelcacheConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'symbols': 'add_symbol'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def kernelcache(self) -> "XnuKernelcache":
        return _wrap(self._impl.kernelcache)

    @kernelcache.setter
    def kernelcache(self, value: "XnuKernelcache") -> None:
        self._impl.kernelcache = _unwrap(value)


class BareboneLinuxKernelConfig:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneLinuxKernelConfig(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'symbols': 'add_symbol'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def kernel(self) -> "LinuxKernelSymbols":
        return _wrap(self._impl.kernel)

    @kernel.setter
    def kernel(self, value: "LinuxKernelSymbols") -> None:
        self._impl.kernel = _unwrap(value)


class BareboneMemoryAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneMemoryAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def check(self) -> None:
        return self._impl.check()

    @property
    def label(self) -> str:
        return self._impl.label

    @property
    def address(self) -> int:
        return self._impl.address

    def __repr__(self):
        return f"BareboneMemoryAddress(label={self.label!r}, address={self.address!r})"


class BareboneInvalidMemoryAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneInvalidMemoryAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class BareboneNonNullMemoryAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.BareboneNonNullMemoryAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class Application:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Application(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def identifier(self) -> str:
        return self._impl.identifier

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def parameters(self) -> dict:
        return self._impl.parameters

    def __repr__(self):
        return f"Application(identifier={self.identifier!r}, name={self.name!r}, pid={self.pid!r})"


class Process:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Process(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def parameters(self) -> dict:
        return self._impl.parameters

    def __repr__(self):
        return f"Process(pid={self.pid!r}, name={self.name!r})"


class Spawn:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Spawn(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def identifier(self) -> str:
        return self._impl.identifier

    def __repr__(self):
        return f"Spawn(pid={self.pid!r}, identifier={self.identifier!r})"


class Child:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Child(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def parent_pid(self) -> int:
        return self._impl.parent_pid

    @property
    def origin(self) -> str:
        return self._impl.origin

    @property
    def identifier(self) -> str:
        return self._impl.identifier

    @property
    def path(self) -> str:
        return self._impl.path

    @property
    def argv(self) -> list[str]:
        return self._impl.argv

    @property
    def envp(self) -> list[str]:
        return self._impl.envp

    def __repr__(self):
        return f"Child(pid={self.pid!r}, parent_pid={self.parent_pid!r}, origin={self.origin!r}, identifier={self.identifier!r}, path={self.path!r})"


class Crash:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Crash(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def process_name(self) -> str:
        return self._impl.process_name

    @property
    def summary(self) -> str:
        return self._impl.summary

    @property
    def report(self) -> str:
        return self._impl.report

    @property
    def parameters(self) -> dict:
        return self._impl.parameters

    def __repr__(self):
        return f"Crash(pid={self.pid!r}, process_name={self.process_name!r}, summary={self.summary!r}, report={self.report!r})"


class Bus:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Bus(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def is_detached(self) -> bool:
        return self._impl.is_detached()

    async def attach(self) -> None:
        return await _invoke(self._impl.attach, ())

    def post(self, message: Any, data: Optional[bytes] = None) -> None:
        json = _to_json(message)
        return self._impl.post(json, data, )

    def _setup(self) -> None:
        self._message_handlers: List[BusMessageCallback] = []
        self._loop = asyncio.get_event_loop()
        self._impl.on("message", self._on_message)

    @overload
    def on(self, signal: Literal["detached"], callback: BusDetachedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["message"], callback: BusMessageCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "message":
            self._message_handlers.append(callback)
        else:
            self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["detached"], callback: BusDetachedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["message"], callback: BusMessageCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "message":
            self._message_handlers.remove(callback)
        else:
            self._impl.off(signal, callback)

    def _on_message(self, raw_message: str, data: Optional[bytes]) -> None:
        message = json.loads(raw_message)
        for handler in list(self._message_handlers):
            _dispatch(self._loop, self._deliver_message, handler, message, data)

    def _deliver_message(self, handler: BusMessageCallback, message: Mapping[Any, Any], data: Optional[bytes]) -> None:
        try:
            handler(message, data)
        except Exception:
            traceback.print_exc()


class Service:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Service(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @overload
    def on(self, signal: Literal["close"], callback: ServiceCloseCallback) -> None: ...
    @overload
    def on(self, signal: Literal["message"], callback: ServiceMessageCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["close"], callback: ServiceCloseCallback) -> None: ...
    @overload
    def off(self, signal: Literal["message"], callback: ServiceMessageCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    @property
    def is_closed(self) -> bool:
        return self._impl.is_closed()

    async def activate(self) -> None:
        return await _invoke(self._impl.activate, ())

    async def cancel(self) -> None:
        return await _invoke(self._impl.cancel, ())

    async def request(self, parameters: Any) -> Any:
        return await _invoke(self._impl.request, (parameters, ))


class Session:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Session(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    @property
    def is_detached(self) -> bool:
        return self._impl.is_detached()

    async def detach(self) -> None:
        return await _invoke(self._impl.detach, ())

    async def resume(self) -> None:
        return await _invoke(self._impl.resume, ())

    async def enable_child_gating(self) -> None:
        return await _invoke(self._impl.enable_child_gating, ())

    async def disable_child_gating(self) -> None:
        return await _invoke(self._impl.disable_child_gating, ())

    async def create_script(self, source: str, name: Optional[str] = None, snapshot: Optional[bytes] = None, runtime: Optional[str] = None) -> "Script":
        options = _frida.ScriptOptions()
        if name is not None:
            options.name = name
        if snapshot is not None:
            options.snapshot = snapshot
        if runtime is not None:
            options.runtime = runtime
        return _wrap(await _invoke(self._impl.create_script, (source, options, )))

    async def create_script_from_bytes(self, data: bytes, name: Optional[str] = None, snapshot: Optional[bytes] = None, runtime: Optional[str] = None) -> "Script":
        bytes = data
        options = _frida.ScriptOptions()
        if name is not None:
            options.name = name
        if snapshot is not None:
            options.snapshot = snapshot
        if runtime is not None:
            options.runtime = runtime
        return _wrap(await _invoke(self._impl.create_script_from_bytes, (bytes, options, )))

    async def compile_script(self, source: str, name: Optional[str] = None, runtime: Optional[str] = None) -> bytes:
        options = _frida.ScriptOptions()
        if name is not None:
            options.name = name
        if runtime is not None:
            options.runtime = runtime
        return await _invoke(self._impl.compile_script, (source, options, ))

    async def snapshot_script(self, embed_script: str, warmup_script: Optional[str] = None, runtime: Optional[str] = None) -> bytes:
        options = _frida.SnapshotOptions()
        if warmup_script is not None:
            options.warmup_script = warmup_script
        if runtime is not None:
            options.runtime = runtime
        return await _invoke(self._impl.snapshot_script, (embed_script, options, ))

    async def setup_peer_connection(self, **kwargs) -> None:
        return await _invoke(self._impl.setup_peer_connection, (_make_options(_frida.PeerOptions, kwargs, {'relays': 'add_relay'}), ))

    async def join_portal(self, address: str, **kwargs) -> "PortalMembership":
        return _wrap(await _invoke(self._impl.join_portal, (address, _make_options(_frida.PortalOptions, kwargs, {}), )))

    @property
    def pid(self) -> int:
        return self._impl.pid

    @property
    def persist_timeout(self) -> int:
        return self._impl.persist_timeout

    def __repr__(self):
        return f"Session(pid={self.pid!r}, persist_timeout={self.persist_timeout!r})"


class Script:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Script(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def is_destroyed(self) -> bool:
        return self._impl.is_destroyed()

    async def load(self) -> None:
        return await _invoke(self._impl.load, ())

    async def interrupt(self) -> None:
        return await _invoke(self._impl.interrupt, ())

    async def unload(self) -> None:
        return await _invoke(self._impl.unload, ())

    async def terminate(self) -> None:
        return await _invoke(self._impl.terminate, ())

    async def eternalize(self) -> None:
        return await _invoke(self._impl.eternalize, ())

    def post(self, message: Any, data: Optional[bytes] = None) -> None:
        json = _to_json(message)
        return self._impl.post(json, data, )

    async def enable_debugger(self, port: int = 0) -> None:
        return await _invoke(self._impl.enable_debugger, (port, ))

    async def disable_debugger(self) -> None:
        return await _invoke(self._impl.disable_debugger, ())

    def _setup(self) -> None:
        self.exports = _ScriptExports(self)
        self._message_handlers: List[ScriptMessageCallback] = []
        self._log_handler: Callable[[str, str], None] = self.default_log_handler
        self._pending: Dict[int, Callable[[Any, Optional[Exception]], None]] = {}
        self._next_request_id = 1
        self._loop = asyncio.get_event_loop()
        self._impl.on("message", self._on_message)
        self._impl.on("destroyed", self._on_destroyed)

    @overload
    def on(self, signal: Literal["destroyed"], callback: ScriptDestroyedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["message"], callback: ScriptMessageCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "message":
            self._message_handlers.append(callback)
        else:
            self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["destroyed"], callback: ScriptDestroyedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["message"], callback: ScriptMessageCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "message":
            self._message_handlers.remove(callback)
        else:
            self._impl.off(signal, callback)

    def get_log_handler(self) -> Callable[[str, str], None]:
        return self._log_handler

    def set_log_handler(self, handler: Callable[[str, str], None]) -> None:
        self._log_handler = handler

    def default_log_handler(self, level: str, text: str) -> None:
        if level == "info":
            print(text, file=sys.stdout)
        else:
            print(text, file=sys.stderr)

    async def list_exports(self) -> List[str]:
        return await self._rpc_request(["list"])

    def _rpc_request(self, args: Any, data: Optional[bytes] = None) -> "asyncio.Future[Any]":
        loop = asyncio.get_running_loop()
        future: "asyncio.Future[Any]" = loop.create_future()

        def complete(value: Any, error: Optional[Exception]) -> None:
            if future.done():
                return
            if error is not None:
                future.set_exception(error)
            else:
                future.set_result(value)

        request_id = self._next_request_id
        self._next_request_id += 1
        self._pending[request_id] = lambda value, error: _dispatch(loop, complete, value, error)

        if self._impl.is_destroyed():
            self._on_destroyed()
        else:
            self.post(["frida:rpc", request_id] + list(args), data)

        return future

    def _on_message(self, raw_message: str, data: Optional[bytes]) -> None:
        message = json.loads(raw_message)
        mtype = message["type"]
        payload = message.get("payload")
        if mtype == "log":
            _dispatch(self._loop, self._log_handler, message["level"], payload)
        elif mtype == "send" and isinstance(payload, list) and payload[:1] == ["frida:rpc"]:
            self._on_rpc_message(payload[1], payload[2], payload[3:], data)
        else:
            for handler in list(self._message_handlers):
                _dispatch(self._loop, self._deliver_message, handler, message, data)

    def _deliver_message(self, handler: ScriptMessageCallback, message: ScriptMessage, data: Optional[bytes]) -> None:
        try:
            handler(message, data)
        except Exception:
            traceback.print_exc()

    def _on_destroyed(self) -> None:
        while True:
            pending_ids = list(self._pending.keys())
            complete = self._pending.pop(pending_ids[0]) if pending_ids else None
            if complete is None:
                break
            complete(None, _frida.InvalidOperationError("script has been destroyed"))

    def _on_rpc_message(self, request_id: int, operation: str, params: List[Any], data: Optional[Any]) -> None:
        if operation not in ("ok", "error"):
            return
        complete = self._pending.pop(request_id, None)
        if complete is None:
            return
        if operation == "error":
            complete(None, RPCException(*params[0:3]))
        elif data is not None:
            complete((params[1], data) if len(params) > 1 else data, None)
        else:
            complete(params[0], None)


class PortalMembership:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PortalMembership(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    async def terminate(self) -> None:
        return await _invoke(self._impl.terminate, ())


class LinuxKernelSymbols:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.LinuxKernelSymbols(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def has_symbol(self, name: str) -> bool:
        return self._impl.has_symbol(name)

    def try_find_symbol(self, name: str) -> Optional[int]:
        return self._impl.try_find_symbol(name)


class LinuxKernelImage:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.LinuxKernelImage(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class LinuxSystemMap:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.LinuxSystemMap(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class XnuKernelcache:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.XnuKernelcache(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()


class PackageManager:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PackageManager(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    async def search(self, query: str, **kwargs) -> "PackageSearchResult":
        return _wrap(await _invoke(self._impl.search, (query, _make_options(_frida.PackageSearchOptions, kwargs, {}), )))

    async def install(self, **kwargs) -> "PackageInstallResult":
        return _wrap(await _invoke(self._impl.install, (_make_options(_frida.PackageInstallOptions, kwargs, {'specs': 'add_spec', 'omits': 'add_omit'}), )))

    @property
    def registry(self) -> str:
        return self._impl.registry

    @registry.setter
    def registry(self, value: str) -> None:
        self._impl.registry = _unwrap(value)

    def __repr__(self):
        return f"PackageManager(registry={self.registry!r})"


class Package:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Package(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def version(self) -> str:
        return self._impl.version

    @property
    def description(self) -> str:
        return self._impl.description

    @property
    def url(self) -> str:
        return self._impl.url

    def __repr__(self):
        return f"Package(name={self.name!r}, version={self.version!r}, description={self.description!r}, url={self.url!r})"


class PackageSearchResult:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PackageSearchResult(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def packages(self) -> list["Package"]:
        return [_wrap(element) for element in self._impl.packages]

    @property
    def total(self) -> int:
        return self._impl.total

    def __repr__(self):
        return f"PackageSearchResult(total={self.total!r})"


class PackageInstallResult:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PackageInstallResult(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def packages(self) -> list["Package"]:
        return [_wrap(element) for element in self._impl.packages]


class ControlService:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.ControlService(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    async def start(self) -> None:
        return await _invoke(self._impl.start, ())

    async def stop(self) -> None:
        return await _invoke(self._impl.stop, ())


class PortalService:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PortalService(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'cluster_endpoints': 'add_cluster_endpoint', 'control_endpoints': 'add_control_endpoint'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def add_cluster_endpoint(self, endpoint_params: "EndpointParameters") -> None:
        return self._impl.add_cluster_endpoint(_unwrap(endpoint_params))

    def add_control_endpoint(self, endpoint_params: "EndpointParameters") -> None:
        return self._impl.add_control_endpoint(_unwrap(endpoint_params))

    async def start(self) -> None:
        return await _invoke(self._impl.start, ())

    async def stop(self) -> None:
        return await _invoke(self._impl.stop, ())

    def kick(self, connection_id: int) -> None:
        return self._impl.kick(connection_id)

    def post(self, connection_id: int, message: Any, data: Optional[bytes] = None) -> None:
        json = _to_json(message)
        return self._impl.post(connection_id, json, data, )

    def narrowcast(self, tag: str, message: Any, data: Optional[bytes] = None) -> None:
        json = _to_json(message)
        return self._impl.narrowcast(tag, json, data, )

    def broadcast(self, message: Any, data: Optional[bytes] = None) -> None:
        json = _to_json(message)
        return self._impl.broadcast(json, data, )

    def enumerate_tags(self, connection_id: int) -> list[str]:
        return self._impl.enumerate_tags(connection_id)

    def tag(self, connection_id: int, tag: str) -> None:
        return self._impl.tag(connection_id, tag)

    def untag(self, connection_id: int, tag: str) -> None:
        return self._impl.untag(connection_id, tag)

    @property
    def device(self) -> "Device":
        return _wrap(self._impl.device)

    @property
    def cluster_params(self) -> "EndpointParameters":
        return _wrap(self._impl.cluster_params)

    @property
    def control_params(self) -> "EndpointParameters":
        return _wrap(self._impl.control_params)

    def _setup(self) -> None:
        self._authenticated_handlers: List[PortalServiceAuthenticatedCallback] = []
        self._message_handlers: List[PortalServiceMessageCallback] = []
        self._loop = asyncio.get_event_loop()
        self._impl.on("authenticated", self._on_authenticated)
        self._impl.on("message", self._on_message)

    @overload
    def on(self, signal: Literal["node-connected"], callback: PortalServiceNodeConnectedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["node-joined"], callback: PortalServiceNodeJoinedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["node-left"], callback: PortalServiceNodeLeftCallback) -> None: ...
    @overload
    def on(self, signal: Literal["node-disconnected"], callback: PortalServiceNodeDisconnectedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["controller-connected"], callback: PortalServiceControllerConnectedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["controller-disconnected"], callback: PortalServiceControllerDisconnectedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["authenticated"], callback: PortalServiceAuthenticatedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["subscribe"], callback: PortalServiceSubscribeCallback) -> None: ...
    @overload
    def on(self, signal: Literal["message"], callback: PortalServiceMessageCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "authenticated":
            self._authenticated_handlers.append(callback)
        elif signal == "message":
            self._message_handlers.append(callback)
        else:
            self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["node-connected"], callback: PortalServiceNodeConnectedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["node-joined"], callback: PortalServiceNodeJoinedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["node-left"], callback: PortalServiceNodeLeftCallback) -> None: ...
    @overload
    def off(self, signal: Literal["node-disconnected"], callback: PortalServiceNodeDisconnectedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["controller-connected"], callback: PortalServiceControllerConnectedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["controller-disconnected"], callback: PortalServiceControllerDisconnectedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["authenticated"], callback: PortalServiceAuthenticatedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["subscribe"], callback: PortalServiceSubscribeCallback) -> None: ...
    @overload
    def off(self, signal: Literal["message"], callback: PortalServiceMessageCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        if signal == "authenticated":
            self._authenticated_handlers.remove(callback)
        elif signal == "message":
            self._message_handlers.remove(callback)
        else:
            self._impl.off(signal, callback)

    def _on_authenticated(self, connection_id: int, raw_session_info: str) -> None:
        session_info = json.loads(raw_session_info)
        for handler in list(self._authenticated_handlers):
            _dispatch(self._loop, self._deliver, handler, connection_id, session_info)

    def _on_message(self, connection_id: int, raw_message: str, data: Optional[bytes]) -> None:
        message = json.loads(raw_message)
        for handler in list(self._message_handlers):
            _dispatch(self._loop, self._deliver, handler, connection_id, message, data)

    def _deliver(self, handler: Callable[..., Any], *args: Any) -> None:
        try:
            handler(*args)
        except Exception:
            traceback.print_exc()


class FileMonitor:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.FileMonitor(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    async def enable(self) -> None:
        return await _invoke(self._impl.enable, ())

    async def disable(self) -> None:
        return await _invoke(self._impl.disable, ())

    @property
    def path(self) -> str:
        return self._impl.path

    def __repr__(self):
        return f"FileMonitor(path={self.path!r})"


class Compiler:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Compiler(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @overload
    def on(self, signal: Literal["starting"], callback: CompilerStartingCallback) -> None: ...
    @overload
    def on(self, signal: Literal["finished"], callback: CompilerFinishedCallback) -> None: ...
    @overload
    def on(self, signal: Literal["output"], callback: CompilerOutputCallback) -> None: ...
    @overload
    def on(self, signal: Literal["diagnostics"], callback: CompilerDiagnosticsCallback) -> None: ...
    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    @overload
    def off(self, signal: Literal["starting"], callback: CompilerStartingCallback) -> None: ...
    @overload
    def off(self, signal: Literal["finished"], callback: CompilerFinishedCallback) -> None: ...
    @overload
    def off(self, signal: Literal["output"], callback: CompilerOutputCallback) -> None: ...
    @overload
    def off(self, signal: Literal["diagnostics"], callback: CompilerDiagnosticsCallback) -> None: ...
    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    async def build(self, entrypoint: str, **kwargs) -> str:
        return await _invoke(self._impl.build, (entrypoint, _make_options(_frida.BuildOptions, kwargs, {'externals': 'add_external'}), ))

    async def watch(self, entrypoint: str, **kwargs) -> None:
        return await _invoke(self._impl.watch, (entrypoint, _make_options(_frida.WatchOptions, kwargs, {'externals': 'add_external'}), ))

    async def build_library(self, entrypoint: str, output_dir: str, **kwargs) -> None:
        return await _invoke(self._impl.build_library, (entrypoint, output_dir, _make_options(_frida.LibraryOptions, kwargs, {}), ))

    async def watch_library(self, entrypoint: str, output_dir: str, **kwargs) -> None:
        return await _invoke(self._impl.watch_library, (entrypoint, output_dir, _make_options(_frida.LibraryOptions, kwargs, {}), ))


class LanguageServer:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.LanguageServer(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    async def start(self) -> None:
        return await _invoke(self._impl.start, ())

    def stop(self) -> None:
        return self._impl.stop()

    def post(self, json: str) -> None:
        return self._impl.post(json)

    @property
    def project_root(self) -> str:
        return self._impl.project_root

    def __repr__(self):
        return f"LanguageServer(project_root={self.project_root!r})"


class PatternCompiler:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternCompiler(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    async def compile(self, entrypoint: str, **kwargs) -> "PatternModule":
        return _wrap(await _invoke(self._impl.compile, (entrypoint, _make_options(_frida.PatternCompileOptions, kwargs, {}), )))


class PatternModule:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternModule(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def lookup(self, name: str) -> "PatternType":
        return _wrap(self._impl.lookup(name))

    async def decode(self, type_name: str, data: bytes, address: int, **kwargs) -> "PatternValue":
        return _wrap(await _invoke(self._impl.decode, (type_name, data, address, _make_options(_frida.PatternDecodeOptions, kwargs, {}), )))

    async def call_function(self, type_name: str, data: bytes, address: int, pattern: int, function: str, **kwargs) -> str:
        return await _invoke(self._impl.call_function, (type_name, data, address, pattern, function, _make_options(_frida.PatternDecodeOptions, kwargs, {}), ))

    @property
    def types(self) -> list["PatternType"]:
        return [_wrap(element) for element in self._impl.types]

    @property
    def root_type(self) -> str:
        return self._impl.root_type

    @property
    def inputs(self) -> list["PatternInput"]:
        return [_wrap(element) for element in self._impl.inputs]

    @property
    def diagnostics(self) -> list["PatternDiagnostic"]:
        return [_wrap(element) for element in self._impl.diagnostics]

    def __repr__(self):
        return f"PatternModule(root_type={self.root_type!r})"


class PatternInput:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternInput(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def type_ref(self) -> "PatternTypeRef":
        return _wrap(self._impl.type_ref)

    def __repr__(self):
        return f"PatternInput(name={self.name!r})"


class PatternType:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternType(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def kind(self) -> str:
        return self._impl.kind

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def doc(self) -> str:
        return self._impl.doc

    @property
    def file(self) -> str:
        return self._impl.file

    @property
    def line(self) -> int:
        return self._impl.line

    @property
    def character(self) -> int:
        return self._impl.character

    @property
    def size(self) -> int:
        return self._impl.size

    @property
    def align(self) -> int:
        return self._impl.align

    @property
    def fields(self) -> list["PatternField"]:
        return [_wrap(element) for element in self._impl.fields]

    @property
    def underlying(self) -> "PatternTypeRef":
        return _wrap(self._impl.underlying)

    @property
    def values(self) -> list["PatternEnumValue"]:
        return [_wrap(element) for element in self._impl.values]

    @property
    def bits(self) -> list["PatternBit"]:
        return [_wrap(element) for element in self._impl.bits]

    @property
    def target(self) -> "PatternTypeRef":
        return _wrap(self._impl.target)

    def __repr__(self):
        return f"PatternType(kind={self.kind!r}, name={self.name!r}, doc={self.doc!r}, file={self.file!r}, line={self.line!r}, character={self.character!r}, size={self.size!r}, align={self.align!r})"


class PatternField:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternField(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def doc(self) -> str:
        return self._impl.doc

    @property
    def hidden(self) -> bool:
        return self._impl.hidden

    @property
    def conditional(self) -> bool:
        return self._impl.conditional

    @property
    def no_unique_address(self) -> bool:
        return self._impl.no_unique_address

    @property
    def type_ref(self) -> "PatternTypeRef":
        return _wrap(self._impl.type_ref)

    @property
    def offset(self) -> int:
        return self._impl.offset

    @property
    def size(self) -> int:
        return self._impl.size

    def __repr__(self):
        return f"PatternField(name={self.name!r}, doc={self.doc!r}, hidden={self.hidden!r}, conditional={self.conditional!r}, no_unique_address={self.no_unique_address!r}, offset={self.offset!r}, size={self.size!r})"


class PatternTypeRef:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternTypeRef(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def kind(self) -> str:
        return self._impl.kind

    @property
    def display(self) -> str:
        return self._impl.display

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def order(self) -> str:
        return self._impl.order

    @property
    def target(self) -> "PatternTypeRef":
        return _wrap(self._impl.target)

    @property
    def width(self) -> "PatternTypeRef":
        return _wrap(self._impl.width)

    @property
    def element(self) -> "PatternTypeRef":
        return _wrap(self._impl.element)

    @property
    def length(self) -> int:
        return self._impl.length

    @property
    def null_terminated(self) -> bool:
        return self._impl.null_terminated

    @property
    def size(self) -> int:
        return self._impl.size

    def __repr__(self):
        return f"PatternTypeRef(kind={self.kind!r}, display={self.display!r}, name={self.name!r}, order={self.order!r}, length={self.length!r}, null_terminated={self.null_terminated!r}, size={self.size!r})"


class PatternEnumValue:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternEnumValue(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def doc(self) -> str:
        return self._impl.doc

    @property
    def value(self) -> int:
        return self._impl.value

    @property
    def last(self) -> int:
        return self._impl.last

    def __repr__(self):
        return f"PatternEnumValue(name={self.name!r}, doc={self.doc!r}, value={self.value!r}, last={self.last!r})"


class PatternBit:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternBit(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def doc(self) -> str:
        return self._impl.doc

    @property
    def kind(self) -> str:
        return self._impl.kind

    @property
    def offset(self) -> int:
        return self._impl.offset

    @property
    def bits(self) -> int:
        return self._impl.bits

    @property
    def enum_name(self) -> str:
        return self._impl.enum_name

    def __repr__(self):
        return f"PatternBit(name={self.name!r}, doc={self.doc!r}, kind={self.kind!r}, offset={self.offset!r}, bits={self.bits!r}, enum_name={self.enum_name!r})"


class PatternDiagnostic:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternDiagnostic(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def file(self) -> str:
        return self._impl.file

    @property
    def line(self) -> int:
        return self._impl.line

    @property
    def character(self) -> int:
        return self._impl.character

    @property
    def message(self) -> str:
        return self._impl.message

    def __repr__(self):
        return f"PatternDiagnostic(file={self.file!r}, line={self.line!r}, character={self.character!r}, message={self.message!r})"


class PatternValue:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternValue(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def to_variant(self) -> Any:
        return self._impl.to_variant()

    @property
    def id(self) -> int:
        return self._impl.id

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def type_name(self) -> str:
        return self._impl.type_name

    @property
    def address(self) -> int:
        return self._impl.address

    @property
    def offset(self) -> int:
        return self._impl.offset

    @property
    def size(self) -> int:
        return self._impl.size

    @property
    def value(self) -> Any:
        return self._impl.value

    @property
    def label(self) -> str:
        return self._impl.label

    @property
    def display_name(self) -> str:
        return self._impl.display_name

    @property
    def formatted(self) -> str:
        return self._impl.formatted

    @property
    def comment(self) -> str:
        return self._impl.comment

    @property
    def color(self) -> str:
        return self._impl.color

    @property
    def hidden(self) -> bool:
        return self._impl.hidden

    @property
    def inlined(self) -> bool:
        return self._impl.inlined

    @property
    def sealed(self) -> bool:
        return self._impl.sealed

    @property
    def bit_offset(self) -> int:
        return self._impl.bit_offset

    @property
    def bits(self) -> int:
        return self._impl.bits

    @property
    def count(self) -> int:
        return self._impl.count

    @property
    def fields(self) -> list["PatternValue"]:
        return [_wrap(element) for element in self._impl.fields]

    @property
    def elements(self) -> list["PatternValue"]:
        return [_wrap(element) for element in self._impl.elements]

    @property
    def truncated(self) -> bool:
        return self._impl.truncated

    @property
    def section(self) -> int:
        return self._impl.section

    @property
    def visualizer(self) -> "PatternVisualizer":
        return _wrap(self._impl.visualizer)

    def __repr__(self):
        return f"PatternValue(id={self.id!r}, name={self.name!r}, type_name={self.type_name!r}, address={self.address!r}, offset={self.offset!r}, size={self.size!r}, label={self.label!r}, display_name={self.display_name!r}, formatted={self.formatted!r}, comment={self.comment!r}, color={self.color!r}, hidden={self.hidden!r}, inlined={self.inlined!r}, sealed={self.sealed!r}, bit_offset={self.bit_offset!r}, bits={self.bits!r}, count={self.count!r}, truncated={self.truncated!r}, section={self.section!r})"


class PatternVisualizer:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternVisualizer(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def to_variant(self) -> Any:
        return self._impl.to_variant()

    @property
    def name(self) -> str:
        return self._impl.name

    @property
    def presentation(self) -> str:
        return self._impl.presentation

    @property
    def arguments(self) -> list["PatternVisualizerArgument"]:
        return [_wrap(element) for element in self._impl.arguments]

    def __repr__(self):
        return f"PatternVisualizer(name={self.name!r}, presentation={self.presentation!r})"


class PatternVisualizerArgument:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.PatternVisualizerArgument(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def to_variant(self) -> Any:
        return self._impl.to_variant()

    @property
    def kind(self) -> str:
        return self._impl.kind

    @property
    def value(self) -> Any:
        return self._impl.value

    @property
    def pattern(self) -> int:
        return self._impl.pattern

    @property
    def address(self) -> int:
        return self._impl.address

    @property
    def size(self) -> int:
        return self._impl.size

    @property
    def data(self) -> bytes:
        return self._impl.data

    def __repr__(self):
        return f"PatternVisualizerArgument(kind={self.kind!r}, pattern={self.pattern!r}, address={self.address!r}, size={self.size!r})"


class StaticAuthenticationService:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.StaticAuthenticationService(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def token_hash(self) -> str:
        return self._impl.token_hash

    def __repr__(self):
        return f"StaticAuthenticationService(token_hash={self.token_hash!r})"


class Relay:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Relay(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def address(self) -> str:
        return self._impl.address

    @property
    def username(self) -> str:
        return self._impl.username

    @property
    def password(self) -> str:
        return self._impl.password

    @property
    def kind(self) -> str:
        return self._impl.kind

    def __repr__(self):
        return f"Relay(address={self.address!r}, username={self.username!r}, password={self.password!r}, kind={self.kind!r})"


class EndpointParameters:
    def __init__(self, address: Optional[str] = None, port: Optional[int] = None, certificate: Optional[str] = None, origin: Optional[str] = None, authentication: Optional[Tuple[str, Any]] = None, asset_root: Optional[str] = None, request_handler: Optional[Callable[..., Any]] = None):
        auth_service = None
        if authentication is not None:
            if isinstance(authentication, tuple):
                scheme, data = authentication
                if scheme == "token":
                    auth_service = _frida.StaticAuthenticationService(data)
                elif scheme == "callback":
                    if not callable(data):
                        raise ValueError("authentication data must be callable for the callback scheme")
                    service = AuthenticationService.__new__(AuthenticationService)
                    service.authenticate = lambda token: json.dumps(data(token))  # type: ignore[attr-defined]
                    AuthenticationService.__init__(service)
                    auth_service = service._impl
                else:
                    raise ValueError("invalid authentication scheme")
            else:
                auth_service = _unwrap(authentication)

        kwargs: Dict[str, Any] = {}
        if address is not None:
            kwargs["address"] = address
        if port is not None:
            kwargs["port"] = port
        if certificate is not None:
            kwargs["certificate"] = certificate
        if origin is not None:
            kwargs["origin"] = origin
        if auth_service is not None:
            kwargs["auth_service"] = auth_service
        if asset_root is not None:
            kwargs["asset_root"] = str(asset_root)

        self._impl = _frida.EndpointParameters(**kwargs)

        if request_handler is not None:
            self._impl.request_handler = _unwrap(request_handler)

    @property
    def address(self) -> str:
        return self._impl.address

    @property
    def port(self) -> int:
        return self._impl.port

    @property
    def certificate(self) -> str:
        return self._impl.certificate

    @property
    def origin(self) -> str:
        return self._impl.origin

    @property
    def auth_service(self) -> "AuthenticationService":
        return _wrap(self._impl.auth_service)

    @property
    def request_handler(self) -> "WebRequestHandler":
        return _wrap(self._impl.request_handler)

    @request_handler.setter
    def request_handler(self, value: "WebRequestHandler") -> None:
        self._impl.request_handler = _unwrap(value)

    def __repr__(self):
        return f"EndpointParameters(address={self.address!r}, port={self.port!r}, origin={self.origin!r})"


class WebRequest:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.WebRequest(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def method(self) -> str:
        return self._impl.method

    @property
    def path(self) -> str:
        return self._impl.path

    @property
    def query_string(self) -> str:
        return self._impl.query_string

    @property
    def body(self) -> bytes:
        return self._impl.body

    def __repr__(self):
        return f"WebRequest(method={self.method!r}, path={self.path!r}, query_string={self.query_string!r})"


class WebResponse:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.WebResponse(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {'headers': 'add_header'})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def add_header(self, name: str, val: str) -> None:
        return self._impl.add_header(name, val)

    @property
    def status(self) -> int:
        return self._impl.status

    @property
    def body(self) -> bytes:
        return self._impl.body

    def __repr__(self):
        return f"WebResponse(status={self.status!r})"


class AuthenticationService(_Implementation):
    def __init__(self):
        self._loop = asyncio.get_event_loop()
        self._impl = _frida.AuthenticationService(self)


class WebRequestHandler(_Implementation):
    def __init__(self):
        self._loop = asyncio.get_event_loop()
        self._impl = _frida.WebRequestHandler(self)


class Cancellable:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.Cancellable(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def on(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.on(signal, _make_signal_handler(callback))

    def off(self, signal: str, callback: Callable[..., Any]) -> None:
        self._impl.off(signal, callback)

    def cancel(self) -> None:
        return self._impl.cancel()

    def get_fd(self) -> int:
        return self._impl.get_fd()

    @property
    def is_cancelled(self) -> bool:
        return self._impl.is_cancelled()

    def pop_current(self) -> None:
        return self._impl.pop_current()

    def push_current(self) -> None:
        return self._impl.push_current()

    def release_fd(self) -> None:
        return self._impl.release_fd()

    def reset(self) -> None:
        return self._impl.reset()

    def set_error_if_cancelled(self) -> bool:
        return self._impl.set_error_if_cancelled()

    def __enter__(self) -> "Cancellable":
        self._token = _current_cancellable.set(self)
        return self

    def __exit__(self, *exc: Any) -> Literal[False]:
        _current_cancellable.reset(self._token)
        return False

    @classmethod
    def get_current(cls) -> "Cancellable":
        return _current_cancellable.get()

    def raise_if_cancelled(self) -> None:
        if self._impl.is_cancelled():
            raise _frida.OperationCancelledError("operation was cancelled")

    def get_pollfd(self) -> "CancellablePollFD":
        return CancellablePollFD(self._impl)


    def _setup(self) -> None:
        self._cancel_handlers: Dict[int, Callable[..., Any]] = {}
        self._next_cancel_handler_id = 1


    def connect(self, callback: Callable[..., Any]) -> int:
        if self._impl.is_cancelled():
            callback()
            return 0

        handler_id = self._next_cancel_handler_id
        self._next_cancel_handler_id = handler_id + 1

        def handler(*args: Any) -> None:
            callback()

        self._cancel_handlers[handler_id] = handler
        self._impl.on("cancelled", handler)
        return handler_id


    def disconnect(self, handler_id: int) -> None:
        handler = self._cancel_handlers.pop(handler_id, None)
        if handler is not None:
            self._impl.off("cancelled", handler)


class IOStream:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.IOStream(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def input_stream(self) -> "InputStream":
        return _wrap(self._impl.input_stream)

    @property
    def output_stream(self) -> "OutputStream":
        return _wrap(self._impl.output_stream)

    @property
    def is_closed(self) -> bool:
        return self._impl.is_closed

    async def close(self) -> None:
        await _invoke(self._impl.close_async, (0,))

    async def read(self, count: int) -> bytes:
        return await _invoke(self._impl.input_stream.read_bytes_async, (count, 0))

    async def read_all(self, count: int) -> bytes:
        chunks = []
        remaining = count
        while remaining > 0:
            chunk = await _invoke(self._impl.input_stream.read_bytes_async, (remaining, 0))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    async def write(self, data: bytes) -> int:
        return await _invoke(self._impl.output_stream.write_bytes_async, (data, 0))

    async def write_all(self, data: bytes) -> None:
        view = memoryview(data)
        while len(view) != 0:
            written = await _invoke(self._impl.output_stream.write_bytes_async, (bytes(view), 0))
            view = view[written:]

    def __repr__(self):
        return f"IOStream(is_closed={self.is_closed!r})"


class InputStream:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.InputStream(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    async def close_async(self, io_priority: int) -> bool:
        return await _invoke(self._impl.close_async, (io_priority, ))

    async def read_bytes_async(self, count: int, io_priority: int) -> bytes:
        return await _invoke(self._impl.read_bytes_async, (count, io_priority, ))

    async def skip_async(self, count: int, io_priority: int) -> int:
        return await _invoke(self._impl.skip_async, (count, io_priority, ))


class OutputStream:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.OutputStream(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    async def close_async(self, io_priority: int) -> bool:
        return await _invoke(self._impl.close_async, (io_priority, ))

    async def flush_async(self, io_priority: int) -> bool:
        return await _invoke(self._impl.flush_async, (io_priority, ))

    async def write_bytes_async(self, bytes: bytes, io_priority: int) -> int:
        return await _invoke(self._impl.write_bytes_async, (bytes, io_priority, ))


class SocketAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.SocketAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def family(self) -> str:
        return self._impl.family

    def get_native_size(self) -> int:
        return self._impl.get_native_size()

    def __repr__(self):
        return f"SocketAddress(family={self.family!r})"


class SocketAddressEnumerator:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.SocketAddressEnumerator(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def next(self, cancellable: Optional["Cancellable"] = None) -> "SocketAddress":
        return _wrap(self._impl.next(_unwrap(cancellable)))

    async def next_async(self) -> "SocketAddress":
        return _wrap(await _invoke(self._impl.next_async, ()))


class SocketConnectable:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.SocketConnectable(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def enumerate(self) -> "SocketAddressEnumerator":
        return _wrap(self._impl.enumerate())

    def proxy_enumerate(self) -> "SocketAddressEnumerator":
        return _wrap(self._impl.proxy_enumerate())

    def to_string(self) -> str:
        return self._impl.to_string()


class InetSocketAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.InetSocketAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def address(self) -> "InetAddress":
        return _wrap(self._impl.address)

    @property
    def flowinfo(self) -> int:
        return self._impl.flowinfo

    @property
    def port(self) -> int:
        return self._impl.port

    @property
    def scope_id(self) -> int:
        return self._impl.scope_id

    def __repr__(self):
        return f"InetSocketAddress(flowinfo={self.flowinfo!r}, port={self.port!r}, scope_id={self.scope_id!r})"


class InetAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.InetAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    def equal(self, other_address: "InetAddress") -> bool:
        return self._impl.equal(_unwrap(other_address))

    @property
    def family(self) -> str:
        return self._impl.family

    @property
    def is_any(self) -> bool:
        return self._impl.is_any

    @property
    def is_link_local(self) -> bool:
        return self._impl.is_link_local

    @property
    def is_loopback(self) -> bool:
        return self._impl.is_loopback

    @property
    def is_mc_global(self) -> bool:
        return self._impl.is_mc_global

    @property
    def is_mc_link_local(self) -> bool:
        return self._impl.is_mc_link_local

    @property
    def is_mc_node_local(self) -> bool:
        return self._impl.is_mc_node_local

    @property
    def is_mc_org_local(self) -> bool:
        return self._impl.is_mc_org_local

    @property
    def is_mc_site_local(self) -> bool:
        return self._impl.is_mc_site_local

    @property
    def is_multicast(self) -> bool:
        return self._impl.is_multicast

    @property
    def is_site_local(self) -> bool:
        return self._impl.is_site_local

    def get_native_size(self) -> int:
        return self._impl.get_native_size()

    def to_string(self) -> str:
        return self._impl.to_string()

    def __repr__(self):
        return f"InetAddress(family={self.family!r}, is_any={self.is_any!r}, is_link_local={self.is_link_local!r}, is_loopback={self.is_loopback!r}, is_mc_global={self.is_mc_global!r}, is_mc_link_local={self.is_mc_link_local!r}, is_mc_node_local={self.is_mc_node_local!r}, is_mc_org_local={self.is_mc_org_local!r}, is_mc_site_local={self.is_mc_site_local!r}, is_multicast={self.is_multicast!r}, is_site_local={self.is_site_local!r})"


class UnixSocketAddress:
    def __init__(self, *args, **kwargs):
        self._impl = _frida.UnixSocketAddress(*[_unwrap(a) for a in args])
        _apply_settings(self._impl, kwargs, {})
        setup = getattr(self, "_setup", None)
        if setup is not None:
            setup()

    @property
    def address_type(self) -> str:
        return self._impl.address_type

    @property
    def path(self) -> str:
        return self._impl.path

    def __repr__(self):
        return f"UnixSocketAddress(address_type={self.address_type!r}, path={self.path!r})"


_WRAPPERS = {
    "GObject": GObject,
    "DeviceManager": DeviceManager,
    "Device": Device,
    "BareboneConfig": BareboneConfig,
    "BareboneConnectionConfig": BareboneConnectionConfig,
    "BareboneAllocatorConfig": BareboneAllocatorConfig,
    "BareboneInvalidAllocatorConfig": BareboneInvalidAllocatorConfig,
    "BarebonePhysicalAllocatorConfig": BarebonePhysicalAllocatorConfig,
    "BareboneTargetFunctionsAllocatorConfig": BareboneTargetFunctionsAllocatorConfig,
    "BareboneCallArgument": BareboneCallArgument,
    "BareboneAgentConfig": BareboneAgentConfig,
    "BareboneInvalidAgentConfig": BareboneInvalidAgentConfig,
    "BareboneInjectedAgentConfig": BareboneInjectedAgentConfig,
    "BareboneResidentAgentConfig": BareboneResidentAgentConfig,
    "BareboneTransportConfig": BareboneTransportConfig,
    "BareboneInjectingTransportConfig": BareboneInjectingTransportConfig,
    "BareboneResidentTransportConfig": BareboneResidentTransportConfig,
    "BareboneHostlinkTransportConfig": BareboneHostlinkTransportConfig,
    "BareboneHostlinkFabric": BareboneHostlinkFabric,
    "BareboneHostlinkEcamFabric": BareboneHostlinkEcamFabric,
    "BareboneHostlinkPortsFabric": BareboneHostlinkPortsFabric,
    "BareboneHostlinkMmioFabric": BareboneHostlinkMmioFabric,
    "BareboneVsockTransportConfig": BareboneVsockTransportConfig,
    "BareboneSerialTransportConfig": BareboneSerialTransportConfig,
    "BareboneVsockPipeTransportConfig": BareboneVsockPipeTransportConfig,
    "BareboneGoldfishPipeTransportConfig": BareboneGoldfishPipeTransportConfig,
    "BareboneDeviceTransportConfig": BareboneDeviceTransportConfig,
    "BareboneSocketTransportConfig": BareboneSocketTransportConfig,
    "BareboneImageConfig": BareboneImageConfig,
    "BareboneInvalidImageConfig": BareboneInvalidImageConfig,
    "BareboneXnuKernelcacheConfig": BareboneXnuKernelcacheConfig,
    "BareboneLinuxKernelConfig": BareboneLinuxKernelConfig,
    "BareboneMemoryAddress": BareboneMemoryAddress,
    "BareboneInvalidMemoryAddress": BareboneInvalidMemoryAddress,
    "BareboneNonNullMemoryAddress": BareboneNonNullMemoryAddress,
    "Application": Application,
    "Process": Process,
    "Spawn": Spawn,
    "Child": Child,
    "Crash": Crash,
    "Bus": Bus,
    "Service": Service,
    "Session": Session,
    "Script": Script,
    "PortalMembership": PortalMembership,
    "LinuxKernelSymbols": LinuxKernelSymbols,
    "LinuxKernelImage": LinuxKernelImage,
    "LinuxSystemMap": LinuxSystemMap,
    "XnuKernelcache": XnuKernelcache,
    "PackageManager": PackageManager,
    "Package": Package,
    "PackageSearchResult": PackageSearchResult,
    "PackageInstallResult": PackageInstallResult,
    "ControlService": ControlService,
    "PortalService": PortalService,
    "FileMonitor": FileMonitor,
    "Compiler": Compiler,
    "LanguageServer": LanguageServer,
    "PatternCompiler": PatternCompiler,
    "PatternModule": PatternModule,
    "PatternInput": PatternInput,
    "PatternType": PatternType,
    "PatternField": PatternField,
    "PatternTypeRef": PatternTypeRef,
    "PatternEnumValue": PatternEnumValue,
    "PatternBit": PatternBit,
    "PatternDiagnostic": PatternDiagnostic,
    "PatternValue": PatternValue,
    "PatternVisualizer": PatternVisualizer,
    "PatternVisualizerArgument": PatternVisualizerArgument,
    "StaticAuthenticationService": StaticAuthenticationService,
    "Relay": Relay,
    "EndpointParameters": EndpointParameters,
    "WebRequest": WebRequest,
    "WebResponse": WebResponse,
    "AuthenticationService": AuthenticationService,
    "WebRequestHandler": WebRequestHandler,
    "Cancellable": Cancellable,
    "IOStream": IOStream,
    "InputStream": InputStream,
    "OutputStream": OutputStream,
    "SocketAddress": SocketAddress,
    "SocketAddressEnumerator": SocketAddressEnumerator,
    "SocketConnectable": SocketConnectable,
    "InetSocketAddress": InetSocketAddress,
    "InetAddress": InetAddress,
    "UnixSocketAddress": UnixSocketAddress,
}
