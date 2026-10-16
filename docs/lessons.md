# Lessons

One line per rule that prevents a mistake that happened.

- Mojo frees a value right after its last use, and `Int(x.unsafe_ptr())` doesn't count as a use: keep buffers you hand to C alive past the C call (e.g. `_ = len(buf)` afterwards).
- Mojo rejects one C function declared with two signatures in a module (even `0` vs a string pointer): pass the same types everywhere, or look the function up with dlsym and cast (`ccall`, `msg`).
- Callbacks from GTK/AppKit can re-enter while a `mut self` method runs; never rely on a Mojo field to block them (keep the flag in the toolkit, or defer work to the next main-loop turn).
- htmx inherits hx-* attributes from ancestors (bit us twice: hx-vals, hx-target). `disableInheritance` (on in mojoui/hosts/web.py) stops most of it, but **hx-vals is still merged from ancestors**: every element must set every hx-vals key it relies on itself.
- A GTK drag gesture reports coordinates relative to the widget it's attached to: never attach it to the widget it moves (jitter); attach it to the container and hit-test.
- Under htmx with `swap: 'none'`, a `<script>` in the response is not executed: send a hidden element with data attributes and let the page's adapter apply it.
- Never sort 20M rows with a comparison sort keyed on a few distinct values (quadratic): gather the column and radix-sort it.

