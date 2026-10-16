@export
def say(n: Int32) abi("C") -> Int32:
    print("hello from Mojo", n)
    return n + 1
