# GOAL 7: Android, with Android's own views

**End goal (owner's words, 2026-10-15):** "one code compile and you get for everything… Android iOS Mac OS Linux and Web at the same time"; "yes to the Android plan… a forty line Java file… is acceptable". The SDK is installed and its licences accepted by the owner (`scripts/android_setup.sh`).

The same `app.mojo` files become Android apps drawn with real Android views (TextView, Button, EditText, Switch, Spinner, SeekBar, LinearLayout…). Mojo creates and updates the views through JNI (Java's C interface, the role `objc_msgSend` plays on Apple). One small Java file in the framework (an Activity plus listeners) forwards Android's callbacks to Mojo; apps contain no Java.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | Toolchain | `scripts/build.sh hello android` makes a signed APK (apksigner verifies it) with libmojoui.so for arm64-v8a and x86_64; the framework's Java is one file of ≤ 80 lines; apps contain no Java |
| M2 | Runs, real touch | on the Android 36 emulator the hello APK starts, shows real Android views, and three real taps (`adb shell input tap`) on Greet show "Hello, Ada! (click 3)" |
| M3 | Components | the gallery's steps (typing, Return, switch, dropdown, slider, reset) through real input end in the same state as on GTK |
| M4 | Todo | the todo app's goal-3 steps through real input end in the same state as on GTK |
| M5 | Layout | the layout example's relations (padding, fixed size, fill, grow, justify, align) hold on Android, measured from the real views' bounds (in dp, within 1.5) |
| M6 | Canvas | the Data Lens runs on Android (CPU path): the canvas shows the map (rich screenshot) and a real swipe pans it as on GTK |
| M7 | Nothing regressed | goal 6's checks still pass |
| M8 | Docs | README status and `docs/android.md` describe what runs, with an Android screenshot |

## Out of bounds
No deploying, store uploads, sign-ups or pushing (unless the owner asks); don't accept licences (the owner did, via the wizard); the emulator may run headless during checks; don't touch `../mojo-ui-apple-test`.

## Assumptions
- Tested on the emulator (x86_64 image; no phone connected). The arm64 library is built and packaged but runs only on a real phone, which the owner can plug in later.
- The Java file is an Activity plus listeners (`View.OnClickListener` etc.): Android only calls Java objects back. The owner approved ~40 lines; an Activity subclass instead of NativeActivity avoids taking the window back from native drawing and Java class-loader traps, at the cost of ~20 more lines (logged).
- Goal-4 components (tabs, alerts, lists…) are a later goal; this one covers the goal-3 components, layout and Canvas.
- Debug signing with a local key made by `keytool` (kept in `build/`, never committed).

## Budget
~3 hours. Stop with a clear report if blocked.
