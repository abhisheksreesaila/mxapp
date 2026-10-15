// M0 smoke-test shell: C owns the loop and calls exported Mojo functions,
// the same shape SDL3's main callbacks will use later.
#include <stdint.h>
#include <stdio.h>

int64_t mojo_app_init(void);
int32_t mojo_app_event(int64_t app, int32_t kind);
void    mojo_app_quit(int64_t app);

int main(void) {
    int64_t app = mojo_app_init();
    printf("[C host] app state lives at 0x%llx\n", (unsigned long long)app);
    for (int i = 0; i < 3; i++) {
        printf("[C host] simulating a button click\n");
        mojo_app_event(app, 1);
    }
    mojo_app_quit(app);
    printf("[C host] done\n");
    return 0;
}
