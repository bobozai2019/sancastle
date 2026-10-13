"""Screenshot tool — capture viewport images from game or editor."""

from __future__ import annotations

from godotiq.bridge.session import get_bridge

VALID_FORMATS = {"webp", "png", "jpg"}
VALID_VIEWPORTS = {"game", "editor"}


async def screenshot(
    viewport: str = "game",
    scale: float = 0.25,
    format: str = "webp",
    quality: float = 0.5,
    camera_position: list[float] | None = None,
    camera_target: list[float] | None = None,
    region: list[float] | None = None,
    session_id: int | None = None,
) -> dict:
    """Capture a screenshot from the game or editor viewport.

    Screenshots are expensive and visual-only. Prefer structured text tools
    for values, scene structure, logs, and errors.

    Args:
        viewport: "game" (default, requires running game) or "editor" (3D editor viewport).
        scale: Image scale factor (0.0-1.0). Default 0.25 for token efficiency.
        format: Image format ("webp", "png", "jpg"). Invalid values fall back to "webp".
        quality: Encoding quality (0.1-1.0). Lower = smaller file. Default 0.5.
        camera_position: [x, y, z] — Editor only. Temporarily move camera here before capture.
        camera_target: [x, y, z] — Editor only. Camera looks at this point.
        region: [x, y, width, height] — Crop region in pixels. Applied before scaling.

    Returns:
        Dict with image (base64), format, width, height.
    """
    if viewport not in VALID_VIEWPORTS:
        return {"error": "Invalid viewport: %s. Use 'game' or 'editor'." % viewport}

    if scale <= 0 or scale > 1.0:
        scale = 0.25
    if format not in VALID_FORMATS:
        format = "webp"
    if quality <= 0 or quality > 1.0:
        quality = 0.5

    if camera_position is not None and len(camera_position) != 3:
        return {"error": "camera_position must have exactly 3 elements [x, y, z]"}
    if camera_target is not None and len(camera_target) != 3:
        return {"error": "camera_target must have exactly 3 elements [x, y, z]"}
    if region is not None:
        if len(region) != 4:
            return {"error": "region must have exactly 4 elements [x, y, width, height]"}
        if region[2] <= 0 or region[3] <= 0:
            return {"error": "region width and height must be positive"}

    bridge = await get_bridge()

    if viewport == "editor":
        params = {"scale": scale, "format": format, "quality": quality}
        if camera_position is not None:
            params["camera_position"] = camera_position
        if camera_target is not None:
            params["camera_target"] = camera_target
        if region is not None:
            params["region"] = region
        result = await bridge.request("editor_screenshot", params=params, timeout=10.0)
    else:
        game_params = {"viewport": viewport, "scale": scale, "format": format, "quality": quality}
        if region is not None:
            game_params["region"] = region
        if session_id is not None:
            game_params["session_id"] = session_id
        # Screenshot work in the game process is synchronous and cannot be
        # cancelled by a client timeout. Retrying here would only enqueue the
        # same expensive capture again after the first request times out.
        result = await bridge.request("screenshot", params=game_params, timeout=32.0)

    # Warn if image is too large for efficient agent context usage
    if isinstance(result, dict) and "error" not in result:
        image_data = result.get("image", "")
        if len(image_data) > 40000:
            result["size_warning"] = (
                "Image is %d chars. Consider using scale=0.15 or quality=0.3 "
                "for smaller output." % len(image_data)
            )

    return result
