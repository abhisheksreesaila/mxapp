# Apple library stubs

Text-based stubs (`.tbd`) that tell the linker which Apple system libraries the
apps load and which functions they use from them. They hold names and install
paths only, no Apple code. They let `ld64.lld` link the Mac and iPhone apps on
Linux without Apple's SDK. At run time the real libraries on the device are used.

If the app starts using a new Apple C function, add it to the matching stub and
to `ALLOWED` in `scripts/check.py`. (Objective-C classes and methods don't need
listing: they are looked up by name at run time.)
