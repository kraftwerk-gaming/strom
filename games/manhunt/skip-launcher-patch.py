#!/usr/bin/env python3
"""
Skip Manhunt PC's startup resolution-picker dialog and pin the engine's
renderer-subsystem mode index to 31 (1920x1080@60 32bpp fullscreen
under our wined3d) by patching manhunt.exe.

The retail PC port (Rockstar North 2003, archive.org preinstalled image
modtime 2022-11-24) unconditionally calls DialogBoxParamA in
FUN_004c0910 before booting the engine. There is no cmdline flag and
pre-seeding HKCU\\Software\\Rockstar Games\\Manhunt\\Video does not
skip the dialog because the registry read lives inside the dialog's
WM_INITDIALOG handler (FUN_004bef40).

Manhunt's video pipeline uses two globals filled by the dialog:

  DAT_00735eb0 = FUN_00612680()  ; renderer subsystem's "current mode"
                                   index (from cmd 0xf -- under wined3d
                                   this resolves to whichever entry of
                                   the engine's mode table matches the
                                   current desktop / gamescope mode).
  DAT_00735eb4 = (from registry/dialog OK handler, defaults to 0)

Both are passed to the renderer subsystem (FUN_006126b0 to set the
device, FUN_00612710 + FUN_00612770 to apply the mode).  If we just
JNZ->JMP the dialog away, DAT_00735eb0 still gets set from
FUN_00612680, but DAT_00735eb4 stays at its BSS-zero default and the
engine boots at the subsystem's mode #0 -- which in our wined3d setup
is a 640x480 fallback render target.

Trying to force higher resolutions by overwriting the FUN_00612710
output buffer with 1920x1080 / 1280x720 / 1024x768 makes the engine
crash inside FUN_0063ce70: its render-target allocator FUN_0063ced0
(vtable[0x58] in the renderer subsystem) returns NULL for those
dimensions, and the subsequent dereference of the NULL RT pointer
faults.  The engine's RT pool is sized for the mode-table entries it
ships with; off-table sizes are unsupported.

So the right pinning is to leave the buffer alone and just seed
DAT_00735eb4 to a sane non-zero value that points at the engine's own
largest-supported mode-table slot.  Under wined3d + a gamescope nested
1920x1080 surface the engine's mode 31 in cmd 6 / cmd 7 resolves to
exactly that 1920x1080 32bpp fullscreen entry (offsets by one against
wined3d's mode_idx 30 because the engine's mode table indexes from 1).
Using mode 31, the engine pre-allocates its render-target pool at
1920x1080 internally, so FUN_0063ced0 succeeds and the depth/stencil
buffer + back buffer both come up at 1920x1080.

Pinning DAT_00735eb4 = 31 also implicitly tells FUN_00612770 (cmd 7,
set color depth) "32 bpp fullscreen", and FUN_004c0830 then finds a
matching D3D8 EnumAdapterModes entry to pin a 60 Hz refresh rate.

If the host's wined3d EnumAdapterModes list differs (different
gamescope nested-surface size, different driver), the right mode
index may shift; rebuild and re-test.

Patches
=======

1) VA 0x4c0991 (file 0xc0791, 7 bytes): replace
       CMP dword [0x735EC0], 0   (83 3D C0 5E 73 00 00)
   with
       E9 rel32 to trampoline    (5 bytes)
       NOP NOP                   (2 bytes)

2) VA 0x4c0998 (file 0xc0798, 2 bytes): replace
       JNZ 0x4c09e7   (75 4D)
   with
       JMP 0x4c09e7   (EB 4D)
   so the dialog block at 0x4c099a..0x4c09e6 is never entered.

3) VA 0x66e086 (file 0x26de86, 15 bytes): install the trampoline in
   the .text NOP/zero tail (executable RX):
       MOV dword [0x735EB4], 31      ; 10 bytes (renderer subsystem
                                       mode index = 1920x1080@60 32bpp
                                       fullscreen under our wined3d).
       JMP rel32 back to 0x4c0998    ; 5 bytes (lands on the JMP
                                       installed by patch 2, which
                                       then jumps to 0x4c09e7).
"""

import struct
import sys

# All VAs use image base 0x00400000. file_offset = VA - 0x400200 in this PE.
VA_TO_FILE_DELTA = 0x400200


def va_to_fo(va: int) -> int:
    return va - VA_TO_FILE_DELTA


# --- Trampoline layout at VA 0x66e086 (within .text NOP/zero tail) ---
#
# x86 encoding used:
#   C7 05 disp32 imm32   MOV dword [disp32], imm32    (10 bytes)
#   E9 rel32             JMP rel32                    ( 5 bytes)
TRAMPOLINE_VA = 0x0066E086


def _u32(x: int) -> bytes:
    return struct.pack("<I", x & 0xFFFFFFFF)


# Trampoline body: hardcode the renderer-subsystem display-mode index into
# DAT_00735eb4 so the post-skip code path of FUN_004c0910 has a valid
# index to pass to FUN_00612710 / FUN_00612770.  Without this seed,
# DAT_00735eb4 is 0 (BSS default) and the engine boots at the subsystem's
# mode #0 -- a 640x480 fallback under our wined3d.
#
# Under wined3d + a 1920x1080 gamescope nested surface, the engine's
# renderer-subsystem mode table indexes (offset by 1 against wined3d's
# own EnumAdapterModes ordering) so mode 31 == wined3d mode_idx 30 ==
# 1920x1080@60 32 bpp fullscreen.  Pinning DAT_00735eb4=31 makes the
# engine pre-allocate its render-target pool at 1920x1080, so the
# resulting swapchain back buffer + depth/stencil come up at native
# 1080p (FUN_0063ced0 is sized by mode-table entry, so off-table sizes
# crash; using the proper mode index avoids that).
TRAMP_BODY = (
    b"\xc7\x05" + _u32(0x00735EB4) + _u32(31)  # MOV [0x735EB4], 31       (10)
)
assert len(TRAMP_BODY) == 10

# Trampoline tail: JMP rel32 back to VA 0x4c0998 (the byte right after the
# 7-byte CMP we displaced).  The original JNZ at 0x4c0998 is left in
# place; control resumes there and either takes the (now-unconditional via
# the second patch) JMP into the post-dialog block, or, if you ever want
# to keep the dialog conditional, the JNZ still does the right thing.
JMP_BACK_FROM_VA = TRAMPOLINE_VA + len(TRAMP_BODY)  # 0x66e090
JMP_BACK_TO_VA = 0x004C0998
_disp_back = JMP_BACK_TO_VA - (JMP_BACK_FROM_VA + 5)
TRAMP_TAIL = b"\xe9" + _u32(_disp_back)

TRAMPOLINE = TRAMP_BODY + TRAMP_TAIL
assert len(TRAMPOLINE) == 15

# --- Call site at VA 0x4c0991: original `CMP [0x735EC0], 0` (7 bytes) ---
# We don't need the CMP anymore (we always skip the dialog via the
# JNZ->JMP at 0x4c0998 below), so we splice in a JMP rel32 to the
# trampoline (5 bytes) + 2 NOPs.  The trampoline writes DAT_00735eb4 and
# returns to 0x4c0998 where our second patch turns the JNZ into JMP.
CALLSITE_VA = 0x004C0991
_disp_fwd = TRAMPOLINE_VA - (CALLSITE_VA + 5)
CALLSITE_NEW = b"\xe9" + _u32(_disp_fwd) + b"\x90\x90"
assert len(CALLSITE_NEW) == 7

# Original: CMP dword [0x735EC0], 0   (83 3D C0 5E 73 00 00)
CALLSITE_OLD = bytes.fromhex("833dc05e730000")
assert len(CALLSITE_OLD) == 7

# Trampoline region is end-of-.text padding: 10 bytes of 0x90 followed by
# 0x00-fill out to the section's raw-size boundary. Either byte value is
# inert as long as we don't execute through it (we JMP in, run our code,
# JMP out). We accept both as the "preimage" rather than insist on 0x90.
TRAMP_OLD_VARIANTS = (
    b"\x90" * len(TRAMPOLINE),
    b"\x90" * 10 + b"\x00" * (len(TRAMPOLINE) - 10),
)


# (file_offset, [accepted_old_bytes], new_bytes, description)
PATCHES = [
    (
        va_to_fo(CALLSITE_VA),
        [CALLSITE_OLD],
        CALLSITE_NEW,
        "VA 0x4c0991: redirect 7-byte CMP through trampoline that seeds DAT_00735eb4=31",
    ),
    (
        0xC0798,
        [bytes.fromhex("754d")],
        bytes.fromhex("eb4d"),
        "VA 0x4c0998: JNZ 0x4c09e7 -> JMP 0x4c09e7 (skip resolution-picker dialog)",
    ),
    (
        va_to_fo(TRAMPOLINE_VA),
        list(TRAMP_OLD_VARIANTS),
        TRAMPOLINE,
        "VA 0x66e086: install DAT_00735eb4=31 trampoline in .text pad tail",
    ),
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: skip-launcher-patch.py <manhunt.exe>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "rb") as f:
        data = bytearray(f.read())

    for offset, accepted_olds, new, description in PATCHES:
        for old in accepted_olds:
            if len(old) != len(new):
                print(
                    f"internal error: patch at 0x{offset:x} expected {len(old)} bytes "
                    f"but replacement is {len(new)} bytes",
                    file=sys.stderr,
                )
                return 1
        n = len(new)
        actual_old = bytes(data[offset : offset + n])
        if actual_old not in accepted_olds:
            print(
                f"error: at file offset 0x{offset:x} found {actual_old.hex()}",
                file=sys.stderr,
            )
            for old in accepted_olds:
                print(f"  expected one of: {old.hex()}", file=sys.stderr)
            print(f"  patch: {description}", file=sys.stderr)
            return 1
        data[offset : offset + n] = new
        print(f"patched 0x{offset:x}: {description}")

    with open(path, "wb") as f:
        f.write(data)
    print(f"wrote {len(data)} bytes to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
