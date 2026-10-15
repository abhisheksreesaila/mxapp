# Report: Android (goal 7)

**End goal (your words):** "one code compile and you get for everything… Android iOS Mac OS Linux and Web"; "yes to the Android plan… a forty line Java file… is acceptable".

**Result:** the same `app.mojo` files now become Android apps drawn with **Android's own views**: TextView, Button, EditText, Switch, Spinner, SeekBar, RadioGroup, ListView, LinearLayout. Mojo creates and updates them through JNI. The app files contain no Java; the framework has one 78-line Java file, because Android only calls Java objects back. Tested on the **Android 16 emulator** with real input (taps, typed keys, Return, swipes). Not yet on a physical phone: the APKs carry the arm64 library a phone needs.

| Hello | Gallery | Todo |
|---|---|---|
| ![Hello](img/android-hello.png) | ![Gallery](img/android-gallery.png) | ![Todo](img/android-todo.png) |

![The Data Lens on Android](img/android-lens.png)

## Checker
```
$ scripts/check
PASS  M1  signed APKs (arm64-v8a + x86_64), one framework Java file (≤ 80 lines), libraries need only Android's libc/libm/liblog
PASS  M2  hello APK runs on Android 16 (emulator); 3 real taps → 'Hello, Ada! (click 3)' in a real TextView
PASS  M3  gallery (typing, Return, switch, dropdown, slider, reset): 13 views identical to GTK after real input
PASS  M4  todo (goal 3's steps): 10 views identical to GTK after real input
PASS  M5  padding, fixed/min/max sizes, fill, grow, justify and align hold on Android (real view bounds, dp)
PASS  M6  lens on Android (CPU, 2M trips) draws the map; a real swipe pans it as on GTK: LABEL: View: centre (0.3667, 0.4333), zoom 1.00×
PASS  M7  goal 6's checks (and goals 3–5's inside them) still pass
PASS  M8  README and docs/android.md describe what runs on Android, with screenshots
```
(One full run on the final code, after two review rounds; the reviewer's verdict: PASS.)

## Try it
```bash
scripts/android_setup.sh                          # once (you did this)
scripts/build.sh todo android
adb install -r build/todo/android/TodoMojo.apk    # phone with USB debugging, or the emulator (AVD "mojoui")
```

## How it works
- **JNI from Mojo** (`mojoui/hosts/jni.mojo`): Java's C interface is a table of functions. Mojo calls them by slot, cast to each call's signature: the same trick as `objc_msgSend` on Apple. The slot numbers come from the JDK's `jni.h`.
- **The host** (`mojoui/hosts/android.mojo`) maps the view tree onto Android views and layout settings onto `LayoutParams`, weights and gravity. The Canvas is an ImageView whose bitmap is filled straight from the app's pixels, with `Choreographer` frames and touch gestures.
- **The one Java file** (`mojoui/hosts/android/MojoActivity.java`) is the Activity. It loads the Mojo library and forwards every callback to it.
- **Proof** (`scripts/android_drive.py`): the gallery and todo test steps end in exactly the same state as on GTK; goal 5's layout rules hold on the real view bounds; a real swipe pans the Data Lens exactly as a drag does on GTK.

## Decisions worth your second look
1. **D-66, an Activity instead of NativeActivity:** the Java file is 78 lines instead of ~40. NativeActivity claims the window for native drawing and can't easily find app classes; an Activity avoids both. It's still one framework file, and apps have none.
2. **D-68, emulator only:** no phone was connected. The arm64 library is built, packaged and signed, but has never run.
3. **D-72, edge to edge:** Android 15+ draws apps under the system bars. Content now fits the bars, and tall screens scroll instead of losing their top. The review's tab-switching test found this.

## Found along the way
- Mojo's timer calls Apple's `clock_gettime_nsec_np` even on Android, so the library wouldn't load. Fixed with `mojoui/clock.mojo`.
- Radio and tab option ids collided with their group's id, so some taps were lost.
- Freeing an app on Android pulled in MAX's GPU functions, even though the GPU path is compiled out. Fixed with two empty stand-ins (D-71).

**Next:** run on a real phone; goal-4 components on Android (alerts, date, icons, nav bar); a phone layout for the Data Lens; then MX frame.
