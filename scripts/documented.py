"""The project's documentation as one text for the archived checks: README.md (the story) plus docs/reference.md
(the API it used to carry: components, layout, the canvas, the examples). D-270: the launch README moved the
reference out; every word the old checks asked the README for must still be in one of the two."""

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def documented():
    return "\n".join((ROOT / p).read_text() for p in ("README.md", "docs/reference.md") if (ROOT / p).exists())
