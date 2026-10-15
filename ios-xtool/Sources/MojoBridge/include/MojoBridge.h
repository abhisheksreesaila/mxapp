#pragma once
#include <stdint.h>

// ---- Exported BY Mojo (prebuilt in Mojo/<platform>/libmojoapp.a) ----
int64_t mojo_app_init(void);                        // opaque app address
int32_t mojo_app_event(int64_t app, int32_t kind);  // kind 1 = "Greet" clicked
void    mojo_app_quit(int64_t app);

// ---- Provided by the C bridge (mojoui_bridge.c) ----
int32_t        mui_version(void);
const uint8_t* mui_last_text(void);                 // last text Mojo sent (not null-terminated)
int32_t        mui_last_text_len(void);
