# Prints every analytics chart as Flint JSON, one per line ("FLINT: {...}"), for scripts/flint_validate.mjs.
# Build: pixi run mojo build -I examples/analytics -I . tests/flint_specs.mojo -o build/flint_specs
from app import Main


def main():
    var app = Main()
    for c in app.charts():
        print("FLINT: " + c.to_json())
