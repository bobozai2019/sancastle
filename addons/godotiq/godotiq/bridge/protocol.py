"""Bridge protocol dataclasses and JSON wire format utilities."""

from __future__ import annotations

import json
from dataclasses import dataclass, field


TOOL_TIMEOUTS: dict[str, float] = {
    "ping": 2.0,
    "screenshot": 30.0,
    "perf_snapshot": 5.0,
    "editor_context": 5.0,
    "run": 10.0,
    "stop": 5.0,
    "scene_tree": 5.0,
    "node_ops": 10.0,
    "build_scene": 30.0,
    "check_errors": 15.0,
    "read_debug_console": 5.0,
    "explore_camera": 10.0,
    "exec_editor": 20.0,
    "exec_game": 20.0,
}

SCREENSHOT_MAX_RETRIES: int = 3
SCREENSHOT_RETRY_DELAY: float = 0.5


def get_timeout(method: str) -> float:
    """Return the configured timeout for a method, defaulting to 5.0s."""
    return TOOL_TIMEOUTS.get(method, 5.0)


@dataclass(frozen=True)
class BridgeRequest:
    """Outgoing request to the Godot addon."""

    id: str
    method: str
    params: dict = field(default_factory=dict)
    token: str | None = None

    def to_json(self) -> str:
        """Serialize to JSON wire format."""
        payload = {"id": self.id, "method": self.method, "params": self.params}
        if self.token:
            payload["token"] = self.token
        return json.dumps(payload)


@dataclass(frozen=True)
class BridgeResponse:
    """Response from the Godot addon."""

    id: str
    status: str
    result: dict | None = None
    error: dict | None = None

    @property
    def is_ok(self) -> bool:
        """Whether this is a successful response."""
        return self.status == "ok"

    @property
    def error_code(self) -> str:
        """Error code from the error dict, or empty string."""
        if self.error:
            return self.error.get("code", "UNKNOWN")
        return ""

    @property
    def error_message(self) -> str:
        """Error message from the error dict, or empty string."""
        if self.error:
            return self.error.get("message", "")
        return ""


@dataclass(frozen=True)
class BridgeEvent:
    """Push event from the Godot addon."""

    event: str
    data: dict = field(default_factory=dict)


def parse_message(text: str) -> BridgeResponse | BridgeEvent:
    """Parse a JSON message from the addon into a response or event.

    Raises ValueError for invalid JSON or unrecognized message format.
    """
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON: {exc}") from exc

    if not isinstance(parsed, dict):
        raise ValueError("Message must be a JSON object")

    if "id" in parsed:
        return BridgeResponse(
            id=str(parsed["id"]),
            status=parsed.get("status", ""),
            result=parsed.get("result"),
            error=parsed.get("error"),
        )
    if "event" in parsed:
        return BridgeEvent(
            event=parsed["event"],
            data=parsed.get("data", {}),
        )
    raise ValueError("Message must contain 'id' or 'event'")
