# Lessons

One line per rule that prevents a mistake that happened.

- Mojo frees a value right after its last use, and `Int(x.unsafe_ptr())` doesn't count as a use: keep buffers you hand to C alive past the C call (e.g. `_ = len(buf)` afterwards).
- Mojo rejects one C function declared with two signatures in a module (even `0` vs a string pointer): pass the same types everywhere, or look the function up with dlsym and cast (`ccall`, `msg`).
- Callbacks from GTK/AppKit can re-enter while a `mut self` method runs; never rely on a Mojo field to block them (keep the flag in the toolkit, or defer work to the next main-loop turn).
