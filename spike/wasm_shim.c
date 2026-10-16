// The runtime a Mojo program needs in WebAssembly (goal 9's spike; see docs/wasm.md): the two
// KGEN allocator entry points and the handful of libc calls the stdlib's stdout path makes.
// Memory: a bump allocator over a static arena (no free); stdout: an imported JS function.
// Built for wasm64: clang --target=wasm64-unknown-unknown -nostdlib -O2 -c spike/wasm_shim.c
typedef unsigned long size_t;
typedef long ssize_t;
#define ARENA_BYTES (64u << 20)
static unsigned char arena[ARENA_BYTES];
static size_t used;

__attribute__((import_module("env"), import_name("mojo_write")))
extern void mojo_write(int fd, const void *buf, size_t len);

void *KGEN_CompilerRT_AlignedAlloc(size_t alignment, size_t size) {
    size_t at = (used + alignment - 1) & ~(alignment - 1);
    if (at + size > ARENA_BYTES) return 0;
    used = at + size;
    return arena + at;
}
void KGEN_CompilerRT_AlignedFree(void *p) { (void)p; }
ssize_t write(long fd, const void *buf, size_t len) { mojo_write((int)fd, buf, len); return (ssize_t)len; }  // (Mojo declares fd as a 64-bit Int)
int dup(int fd) { return fd; }
void *fdopen(int fd, const char *mode) { (void)mode; return (void *)(long)(fd + 1); }
int fclose(void *f) { (void)f; return 0; }
int fflush(void *f) { (void)f; return 0; }
