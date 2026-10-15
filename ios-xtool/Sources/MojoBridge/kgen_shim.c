// EXPERIMENT ONLY: stand-ins for the two Mojo runtime functions this app needs.
// Signatures inferred from call sites (align, size) and (ptr); unofficial, may change.
#include <stdlib.h>
#include <stddef.h>

void* KGEN_CompilerRT_AlignedAlloc(size_t align, size_t size) {
    if (align < sizeof(void*)) align = sizeof(void*);
    void* p = NULL;
    if (posix_memalign(&p, align, size ? size : 1) != 0) return NULL;
    return p;
}

void KGEN_CompilerRT_AlignedFree(void* p) { free(p); }
