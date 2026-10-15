# Probe: one C symbol called with different signatures via OwnedDLHandle,
# and a Mojo abi("C") function passed to C as a callback.
from std.ffi import OwnedDLHandle, external_call, c_int, c_size_t

def cmp(a: Int, b: Int) abi("C") -> c_int:
    var x = Pointer[Int64, MutUntrackedOrigin](unsafe_from_address=a)[]
    var y = Pointer[Int64, MutUntrackedOrigin](unsafe_from_address=b)[]
    if x < y:
        return -1
    return c_int(x > y)

def main() raises:
    var proc = OwnedDLHandle()
    var labs = proc.get_function[Int]("labs")
    print("labs(-7) =", labs(Int(-7)))
    var fabs = proc.get_function[Float64]("fabs")
    print("fabs(-2.5) =", fabs(Float64(-2.5)))
    var nums: List[Int64] = [5, 2, 9, 1]
    external_call["qsort", NoneType](Int(nums.unsafe_ptr()), c_size_t(4), c_size_t(8), cmp)
    print("sorted:", nums)
