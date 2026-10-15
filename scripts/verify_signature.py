"""Independent check of a Mach-O code signature (ad-hoc or not).

Recomputes the hash of every code page and of Info.plist and compares them with
the CodeDirectory, the same hashes the kernel checks before running the app.
Usage: python scripts/verify_signature.py <executable> [<Info.plist>]
"""

import hashlib
import struct
import sys

LC_CODE_SIGNATURE = 0x1D
HASHES = {1: hashlib.sha1, 2: hashlib.sha256}


def verify(exe_path, plist_path=None):
    data = open(exe_path, "rb").read()
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    assert magic == 0xFEEDFACF, "not a 64-bit Mach-O"
    off, sig = 32, None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == LC_CODE_SIGNATURE:
            sig = struct.unpack_from("<II", data, off + 8)
        off += size
    if not sig:
        return ["no LC_CODE_SIGNATURE"]
    dataoff, datasize = sig
    problems = []
    if dataoff + datasize != len(data):
        problems.append(f"{len(data) - dataoff - datasize} stray bytes after the signature")
    blob = data[dataoff:dataoff + datasize]
    smagic, _, count = struct.unpack_from(">III", blob, 0)
    assert smagic == 0xFADE0CC0, "no embedded signature superblob"
    cds = []
    for i in range(count):
        btype, boff = struct.unpack_from(">II", blob, 12 + 8 * i)
        if struct.unpack_from(">I", blob, boff)[0] == 0xFADE0C02:
            cds.append((btype, boff))
    if not cds:
        return problems + ["no CodeDirectory"]
    for _, cd in cds:
        (_, _, _, _, hash_off, _, n_special, n_code, code_limit, hash_size, hash_type, _, page_log2) = \
            struct.unpack_from(">IIIIIIIIIBBBB", blob, cd)
        h = HASHES[hash_type]
        page = 1 << page_log2
        for i in range(n_code):
            want = blob[cd + hash_off + i * hash_size: cd + hash_off + (i + 1) * hash_size]
            got = h(data[i * page: min((i + 1) * page, code_limit)]).digest()[:hash_size]
            if got != want:
                problems.append(f"code page {i} hash mismatch")
                break
        if plist_path and n_special >= 1:
            want = blob[cd + hash_off - hash_size: cd + hash_off]
            got = h(open(plist_path, "rb").read()).digest()[:hash_size]
            if got != want:
                problems.append("Info.plist hash mismatch")
    return problems


if __name__ == "__main__":
    problems = verify(*sys.argv[1:3])
    print("signature OK" if not problems else "; ".join(problems))
    sys.exit(1 if problems else 0)
