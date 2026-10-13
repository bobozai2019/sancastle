"""Async WebSocket client for communicating with the Godot editor addon."""

from __future__ import annotations

import asyncio
from typing import Any, Callable

from godotiq.bridge.protocol import BridgeRequest, parse_message, BridgeResponse, BridgeEvent, get_timeout


class BridgeConnectionError(Exception):
    """Raised when the bridge is not connected or connection fails."""


class BridgeTimeoutError(Exception):
    """Raised when a request times out waiting for a response."""


class BridgeError(Exception):
    """Raised when the addon returns an error response."""

    def __init__(self, code: str, error_message: str) -> None:
        self.code = code
        self.error_message = error_message
        super().__init__(f"[{code}] {error_message}")


class BridgeConnection:
    """Async WebSocket client for the Godot addon bridge."""

    def __init__(self, host: str = "127.0.0.1", port: int = 6107, token: str = "") -> None:
        self._host = host
        self._port = port
        self._token = token
        self._ws: Any = None
        self._pending: dict[str, asyncio.Future[BridgeResponse]] = {}
        self._event_handlers: dict[str, list[Callable]] = {}
        self._request_counter: int = 0
        self._connected: bool = False
        self._game_running: bool = False
        self._listen_task: asyncio.Task[None] | None = None

    @property
    def is_connected(self) -> bool:
        """Whether the bridge is currently connected."""
        return self._connected

    @property
    def is_game_running(self) -> bool:
        """Whether the Godot game is currently running."""
        return self._game_running

    async def connect(self, timeout: float = 5.0) -> None:
        """Connect to the Godot addon WebSocket server.

        Imports websockets lazily to avoid import-time failures before
        the dependency is installed.
        """
        try:
            import websockets
        except ImportError as exc:
            raise BridgeConnectionError(
                "websockets package not installed. Install with: pip install websockets"
            ) from exc

        try:
            self._ws = await asyncio.wait_for(
                websockets.connect(
                    f"ws://{self._host}:{self._port}",
                    max_size=16 * 1024 * 1024,
                ),
                timeout=timeout,
            )
        except Exception as exc:
            raise BridgeConnectionError(f"Failed to connect to {self._host}:{self._port}: {exc}") from exc

        self._connected = True
        self._game_running = False
        # Register internal handlers only once (clear any from previous connection)
        self._event_handlers.pop("game_started", None)
        self._event_handlers.pop("game_stopped", None)
        self.on_event("game_started", self._on_game_started)
        self.on_event("game_stopped", self._on_game_stopped)
        self._listen_task = asyncio.create_task(self._listen_loop())

    async def disconnect(self) -> None:
        """Disconnect from the addon and clean up."""
        if self._listen_task and not self._listen_task.done():
            self._listen_task.cancel()
            try:
                await self._listen_task
            except asyncio.CancelledError:
                pass
        self._listen_task = None

        if self._ws:
            await self._ws.close()
            self._ws = None

        for future in self._pending.values():
            if not future.done():
                future.set_exception(BridgeConnectionError("Disconnected"))
        self._pending.clear()
        self._connected = False
        self._game_running = False

    async def request(self, method: str, params: dict | None = None, timeout: float | None = None) -> dict:
        """Send a request and await the response.

        Returns the result dict on success.
        Raises BridgeConnectionError if not connected.
        Raises BridgeTimeoutError if the request times out.
        Raises BridgeError if the addon returns an error.
        """
        if not self._connected:
            raise BridgeConnectionError("Not connected to Godot addon")

        self._request_counter += 1
        req_id = str(self._request_counter)
        req = BridgeRequest(id=req_id, method=method, params=params or {}, token=self._token)

        loop = asyncio.get_running_loop()
        future: asyncio.Future[BridgeResponse] = loop.create_future()
        self._pending[req_id] = future

        try:
            await self._ws.send(req.to_json())
        except Exception as exc:
            self._pending.pop(req_id, None)
            raise BridgeConnectionError(f"Failed to send request: {exc}") from exc

        effective_timeout = timeout if timeout is not None else get_timeout(method)
        try:
            response = await asyncio.wait_for(future, timeout=effective_timeout)
        except asyncio.TimeoutError:
            self._pending.pop(req_id, None)
            raise BridgeTimeoutError(f"Request '{method}' timed out after {effective_timeout}s")

        if response.is_ok:
            return response.result or {}
        raise BridgeError(response.error_code, response.error_message)

    async def request_with_retry(
        self,
        method: str,
        params: dict | None = None,
        max_retries: int = 3,
        retry_delay: float = 0.5,
    ) -> dict:
        """Send a request with automatic retry on timeout or error.

        BridgeConnectionError is never retried.
        """
        last_exc: Exception | None = None
        for attempt in range(max_retries):
            try:
                return await self.request(method, params)
            except BridgeConnectionError:
                raise
            except (BridgeTimeoutError, BridgeError) as exc:
                last_exc = exc
                if attempt < max_retries - 1:
                    await asyncio.sleep(retry_delay)
        raise last_exc  # type: ignore[misc]

    def on_event(self, event: str, handler: Callable) -> None:
        """Register an event handler."""
        if event not in self._event_handlers:
            self._event_handlers[event] = []
        self._event_handlers[event].append(handler)

    def _dispatch_event(self, event: str, data: dict) -> None:
        """Dispatch an event to all registered handlers."""
        for handler in self._event_handlers.get(event, []):
            handler(data)

    def _on_game_started(self, data: dict) -> None:
        """Internal handler for game_started events."""
        self._game_running = True

    def _on_game_stopped(self, data: dict) -> None:
        """Internal handler for game_stopped events."""
        self._game_running = False

    async def _listen_loop(self) -> None:
        """Background task that reads incoming messages from the WebSocket."""
        try:
            async for raw in self._ws:
                try:
                    msg = parse_message(raw)
                except ValueError:
                    continue

                if isinstance(msg, BridgeResponse):
                    future = self._pending.pop(msg.id, None)
                    if future and not future.done():
                        future.set_result(msg)
                elif isinstance(msg, BridgeEvent):
                    self._dispatch_event(msg.event, msg.data)
        except asyncio.CancelledError:
            raise
        except Exception:
            pass
        finally:
            for future in self._pending.values():
                if not future.done():
                    future.set_exception(BridgeConnectionError("Connection lost"))
            self._pending.clear()
            self._connected = False
