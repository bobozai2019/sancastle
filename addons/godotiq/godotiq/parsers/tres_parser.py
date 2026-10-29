"""Parser for Godot .tres resource files.

Extracts resource definitions from Godot's text resource format.
"""


def parse_tres(content: str) -> dict:
    """Parse a .tres file's text content into a resource dictionary.

    Args:
        content: Raw text content of a .tres file.

    Returns:
        Parsed resource representation.

    Raises:
        NotImplementedError: Parser not yet implemented (Sprint 0 placeholder).
    """
    raise NotImplementedError("tres parser not yet implemented")
