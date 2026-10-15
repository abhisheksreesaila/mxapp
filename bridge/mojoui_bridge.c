// M0 smoke-test bridge: proves Mojo -> C calls work with scalars and (ptr, len) strings.
// Also keeps the last text Mojo sent, so a SwiftUI skin can read it back (M5).
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint8_t g_last_text[256];
static int32_t g_last_len = 0;

int32_t mui_version(void) { return 1; }

// (ptr, len) string in, no null terminator required.
int32_t mui_echo(const uint8_t* text, int32_t len) {
    int32_t n = len < (int32_t)sizeof(g_last_text) ? len : (int32_t)sizeof(g_last_text);
    if (n > 0) memcpy(g_last_text, text, (size_t)n);
    g_last_len = n > 0 ? n : 0;
    printf("[C bridge] received %d bytes: %.*s\n", len, len, (const char*)text);
    fflush(stdout);
    return len;
}

// Read back the last text Mojo sent (not null-terminated; use the length).
const uint8_t* mui_last_text(void) { return g_last_text; }
int32_t mui_last_text_len(void) { return g_last_len; }
