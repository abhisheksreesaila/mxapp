# Android: what works, what's blocked, and the plan

Status: blocked (needs your decision and Google's SDK licence; see "What needs you")

## Works today (checked on Linux)
- **Mojo targets Android.** `mojo build --target-triple aarch64-linux-android29 --emit object` compiles mojoui apps as they are (all but the GPU example, which needs NVIDIA/AMD).
- **A real Android library.** `scripts/build.sh todo android` builds `build/todo/android/lib/arm64-v8a/libmojoui.so`, 37 KB: the todo app plus the mojoui core, with the `ANativeActivity_onCreate` entry Android calls on the UI thread. It needs only Android's own `libc` and `liblog`. There's no Mojo runtime library (the runtime functions are Mojo, `mojoui/hosts/mojo_rt.mojo`) and no Java.
- It's linked on Linux by `ld.lld` against empty libraries that carry only the system libraries' names, the same trick as `apple/sdk/`.

`hosts/android_main.mojo` creates the app and logs its first screen ("TodoMojo: first screen has N nodes…"). It doesn't draw anything yet.

## The plan for native Android widgets
Same idea as Apple: Mojo drives the platform's own UI toolkit directly.

1. **Drawing:** Android's views are Java objects, and JNI gives native code a table of functions to create and call them (`FindClass`, `NewObjectA`, `CallVoidMethodA`…). That's the same role `objc_msgSend` plays on Apple, so `mojoui/hosts/android.mojo` would map the view tree onto `LinearLayout`, `TextView`, `Button`, `EditText`, `CheckBox`, `Spinner`, `SeekBar`, `ProgressBar` and `ImageView`. The non-variadic `…A` JNI calls take arguments as an array, which Mojo can build easily.
2. **Getting the screen:** NativeActivity claims the window for native drawing. `getWindow().takeSurface(null)` gives it back, so `setContentView` can show normal views.
3. **Events** are the real blocker: Android only delivers a tap to a *Java object implementing a listener interface* (`View.OnClickListener` …), and native code can't create such a class without Java bytecode. The options, most "Mojo all the way" first:
   - **a) Polling, no Java at all:** a timer on the UI thread's looper (`ALooper_addFd` with a `timerfd`) checks widget state every frame. Text, checkboxes, spinners and sliders all keep their state, so changes can be read. For taps, use `ToggleButton`s styled as buttons (each tap flips them). It's hacky but pure Mojo, and it costs a little battery.
   - **b) A tiny listener class, ~40 lines of Java**, that forwards every event to one Mojo function (`RegisterNatives`). This is the standard way, the most robust, and needs `d8` to compile it.
   - **c) A hand-built dex** (Java bytecode file) embedded in the Mojo library and loaded at run time (`InMemoryDexClassLoader`). This is option b without Java source, but generating dex by hand is a project of its own.
   - **Recommendation:** (b). It's one small, boring file, and the rest stays Mojo.
4. **Packaging an APK:** the APK needs a binary `AndroidManifest.xml` (aapt2, or a small encoder we write), the library, the dex for (b), and an APK v2 signature (apksigner).

## What needs you
- **A decision:** is a ~40-line Java listener shim (option b) acceptable, or should Android stay Mojo-only (option a, polling)?
- **The Android SDK licence:** aapt2, apksigner, d8 and the emulator come from Google's SDK, which needs you to accept Google's licence (`sdkmanager --licenses`). I didn't accept it for you.
- **A device or emulator to test on:** there's none here. With an Android phone in developer mode, `adb install` is enough. Arch's `android-tools` package provides `adb` without the SDK.

## Evidence
```
$ scripts/build.sh todo android
$ file build/todo/android/lib/arm64-v8a/libmojoui.so
ELF 64-bit LSB shared object, ARM aarch64, version 1 (SYSV), dynamically linked
$ llvm-readelf -d …/libmojoui.so | grep NEEDED
libc.so  liblog.so
$ llvm-nm -D --undefined-only …/libmojoui.so
__android_log_write dup fclose fdopen fflush free memcpy posix_memalign strlen write
```
