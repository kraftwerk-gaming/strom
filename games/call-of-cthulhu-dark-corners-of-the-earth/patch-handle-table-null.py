#!/usr/bin/env python3
r"""
Round-14 RE patch for Call of Cthulhu: Dark Corners of the Earth.

The build is CoCMainWin32.exe with file md5 b337435749b8598ed1fa597a2de105b7
(GOG v1.0(a) build 33564).

Round-14 RE patch: with round-12+13's case + cwd symlink fixes the engine
now progresses through font init, the full D3D9 shader set, and 237
relative asset opens before hitting a NULL deref at VA 0x0056c3c9 inside
a templated handle-wrapper destructor. WINEDEBUG=+file shows the moments
before the crash are dominated by DirectShow video-codec enumeration that
fails — msrle32.dll, msvidc32.dll, iccvid.dll, and especially ir50_32.dll
(Indeo Video 5, the codec DCoTE's intro FMVs require). Wine's quartz +
devenum + qasf load successfully, but none of the codec DLLs are present
under any of the searched paths (the engine cwd, all wine system32
locations, Program Files\\Steam). The filter-graph construction fails
partway through and the engine's smart-pointer wrapper for the codec
object ends up with a non-NULL outer holder but a NULL inner ptr.

The crashing function at VA 0x0056c3a0 is a templated 2-slot destructor:
  push esi; mov esi, ecx               ; this = ecx
  push edi
  mov edi, [esi]; test edi, edi; jz s1 ; field0 = this->[0]
    mov ecx, edi; call 0x56cab0        ; field0 cleanup
    push edi; call 0x40c6e0; add esp,4 ; free(field0)
  s1:
  mov edi, [esi+8]; test edi, edi      ; field2 = this->[8]
  mov [esi], 0
  jz end
    mov eax, [edi]                     ; inner = field2->[0]
0x56c3c9:
    mov ecx, [eax]                     ; CRASH: load vtable from NULL
    push eax; call [ecx+8]             ; vtable[2](inner) - Release/Free?
    test eax,eax; jne s2
      mov ecx,[edi+4]; push edi
      call 0x56d90                     ; free wrapper
    s2:
    mov [esi+8], 0
  end:
  pop edi; pop esi; ret

Called from VA 0x0056be44 inside a larger destructor on field [esi+0x14]
of a parent singleton (function at 0x0056bbc0). This parent iterates many
similar member slots — typical of a static-manager destructor for an
asset/codec registry. The pattern matches a half-constructed
filter-graph wrapper whose outer holder allocated but inner codec init
returned NULL.

Adding codec DLLs at build time isn't feasible (winetricks needs
network and is multi-hour; vmstack issues under nix-build sandbox). NULL-
guard the inner-ptr deref: plant a trampoline at the .text trailing zero
pad (file_off 0x2274e9 onward) and replace the 5-byte
``mov eax,[edi]; mov ecx,[eax]; push eax`` sequence with a 5-byte rel32
jump to the trampoline. The trampoline:
  - loads eax = [edi]
  - if eax==NULL: jumps past the call to 0x56c3cf (the test eax,eax
    after the call). With eax=0, the test+jne falls through to the
    free path (0x56c3d3) which then frees the wrapper - the same code
    path the function takes when the call returned eax=0 anyway.
  - if eax!=NULL: restores the original ``mov ecx,[eax]; push eax``
    and jumps back to the call site at 0x56c3cc.

The result is: when the inner codec ptr is NULL, the engine skips the
vtable Release call and proceeds to free the wrapper anyway. Equivalent
to what would have happened if Release returned 0, just without
crashing on the NULL vtable load.

Patch byte layout:
  VA 0x56c3c7 (file_off 0x16c3c7), 5 bytes:
    8b 07 8b 08 50      =>  e9 1d b1 0b 00
  VA 0x6274e9 (file_off 0x2274e9), 19 bytes:
    19x 00              =>  8b 07 85 c0 75 05 e9 db 4e f4 ff
                            8b 08 50 e9 d0 4e f4 ff
"""

import hashlib
import sys
from pathlib import Path

SRC = Path(sys.argv[1])
DST = Path(sys.argv[2])

data = bytearray(SRC.read_bytes())

# Sanity-check the build matches the RE.
expected_md5 = "b337435749b8598ed1fa597a2de105b7"

actual_md5 = hashlib.md5(data).hexdigest()
if actual_md5 != expected_md5:
    print(
        f"ERROR: CoCMainWin32.exe md5 {actual_md5} != expected {expected_md5}; "
        "the round-14 RE addresses may not apply to this build. Re-do RE.",
        file=sys.stderr,
    )
    sys.exit(1)


def patch(offset, expected, replacement):
    actual = bytes(data[offset : offset + len(expected)])
    if actual != expected:
        print(
            f"ERROR: at file offset 0x{offset:x}, expected {expected.hex()}, "
            f"got {actual.hex()}. Skipping patch.",
            file=sys.stderr,
        )
        sys.exit(1)
    data[offset : offset + len(replacement)] = replacement
    print(f"  patched 0x{offset:x}: {expected.hex()} -> {replacement.hex()}")


# Round-14 site 1: VA 0x56c3c7 (file_off 0x16c3c7), 5 bytes.
# Original: mov eax,[edi]; mov ecx,[eax]; push eax  (8b 07 8b 08 50)
# Patched:  jmp 0x6274e9                            (e9 1d b1 0b 00)
patch(
    offset=0x0016C3C7,
    expected=bytes.fromhex("8b078b0850"),
    replacement=bytes.fromhex("e91db10b00"),
)

# Round-14 site 2: VA 0x6274e9 (file_off 0x2274e9), 19 bytes of zero pad
# in the .text trailing pad. Body:
#   8b 07              mov eax, [edi]
#   85 c0              test eax, eax
#   75 05              jne +5 (skip the NULL-case jmp)
#   e9 db 4e f4 ff     jmp 0x56c3cf  (NULL case: skip vtable call;
#                                     test eax,eax with eax=0 falls into
#                                     the free path at 0x56c3d3 -> 0x56d90)
#   8b 08              mov ecx, [eax]  (original instr 2)
#   50                 push eax        (original instr 3)
#   e9 d0 4e f4 ff     jmp 0x56c3cc    (back to call [ecx+8])
patch(
    offset=0x002274E9,
    expected=bytes(19),
    replacement=bytes.fromhex("8b0785c07505e9db4ef4ff8b0850e9d04ef4ff"),
)

DST.write_bytes(bytes(data))
print(f"wrote patched binary to {DST}")
