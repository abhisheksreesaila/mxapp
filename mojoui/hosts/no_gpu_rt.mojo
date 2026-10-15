# Stand-ins for the two MAX runtime functions a CPU-only build (Android) still names.
#
# PointCloud's GPU fields (Optional DeviceContext / DeviceBuffer) are always empty when the
# GPU path is compiled out, but their destructors are still compiled in (they run when an
# app is freed), and those name MAX's release functions. They're never called with a value;
# these empty versions only satisfy the linker. Linked into Android builds only.


@export("AsyncRT_DeviceBuffer_release")
def device_buffer_release(buffer: Int) abi("C"):
    pass


@export("AsyncRT_DeviceContext_release")
def device_context_release(context: Int) abi("C"):
    pass
