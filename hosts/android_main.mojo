# Android entry point: the app module (`app.mojo`, chosen with -I) built into libmojoui.so.
# MojoActivity.java (the framework's one Java file) loads it and calls these native methods;
# JNI finds them by name (Java_<package>_<class>_<method>).
from app import Main
from mojoui.hosts.android import android_create, android_event, android_touch, android_frame, android_row


@export("Java_dev_mojoui_MojoActivity_create")
def jni_create(env: Int, cls: Int, activity: Int) abi("C") -> Int:
    return android_create[Main](env, activity)


@export("Java_dev_mojoui_MojoActivity_event")
def jni_event(env: Int, cls: Int, host: Int, view: Int32, kind: Int32, text: Int, number: Int32) abi("C"):
    android_event[Main](env, host, Int(view), Int(kind), text, Int(number))


@export("Java_dev_mojoui_MojoActivity_touch")
def jni_touch(
    env: Int, cls: Int, host: Int, view: Int32, action: Int32, x: Float32, y: Float32, x2: Float32, y2: Float32, pointers: Int32
) abi("C"):
    android_touch[Main](env, host, Int(view), Int(action), Float64(x), Float64(y), Float64(x2), Float64(y2), Int(pointers))


@export("Java_dev_mojoui_MojoActivity_frame")
def jni_frame(env: Int, cls: Int, host: Int, nanos: Int) abi("C"):
    android_frame[Main](env, host, nanos)


@export("Java_dev_mojoui_MojoActivity_row")
def jni_row(env: Int, cls: Int, host: Int, view: Int32, index: Int32) abi("C") -> Int:
    return android_row[Main](env, host, Int(view), Int(index))


@export("JNI_OnLoad")
def jni_on_load(vm: Int, reserved: Int) abi("C") -> Int32:
    """Android calls this when the library loads: the JNI version we use (1.6)."""
    return Int32(0x00010006)
