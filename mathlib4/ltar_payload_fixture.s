# SPDX-License-Identifier: Apache-2.0
# Self-contained LTAR with Zstandard streams and an LGZ-encoded theorem.
.macro raw_header size
.long 0xfd2fb528
.byte 0x20, \size
.word ((\size) << 3) | 1
.byte 0
.endm

.macro skip_empty
.long 0x184d2a50, 0
.endm

.section .ltar_payload,"a",@progbits
.ascii "LTR2"
.quad 43
.asciz "tiny.trace"
.byte 3
.quad 18446744073709551615
.asciz "tiny.bin"
.byte 0
.quad .Lbinary_end-.Lbinary
.Lbinary:
.long 0xfd2fb528
.byte 0x20, 5, 41, 0, 0            # single segment, size 5, last raw block
.byte 0, 10, 255, 92, 0
.Lbinary_end:
.asciz "lib/Tiny.olean"
.byte 1
.quad .Llgz_end-.Lframe
.Lframe:
raw_header (.Lpart1_end-.Llgz)
.Llgz:
.ascii "LGZ2"
.long 0x12345678
.quad 0                             # allocation hint
.ascii "6caaee842e"                 # split the LGZ header inside its githash
.Lpart1_end:
skip_empty
raw_header 0
raw_header (.Lpart2_end-.Lpart2)
.Lpart2:
.ascii "9495688c1567e78c0e68dbb96942aa"
.byte 1, 4, 19, 0, 255
.byte 0x0a                          # ModuleData (five object fields)
.byte 0xff, 0, 0xd0                 # imports; save the empty array at slot 0
.byte 0, 0xd1                       # declaration names
.byte 0xff, 0x80, 0, 0xd0, 0x30     # save Name.str at slot 1
.ascii "cacheStage"                 # break inside the saved Name.str object
.Lpart2_end:
raw_header (.Llgz_end-.Lpart3)
.Lpart3:
.asciz "Six"
.byte 0, 0xd1, 0x22, 0x06           # constants, thmInfo, theorem value
.byte 0x06, 0xf1, 0xd0              # ConstantVal name and levelParams
.byte 0x80, 0x40, 0xff, 0, 0xd0, 0x30  # type Expr.const True; name saved at 2
.asciz "True"
.byte 0xd0                          # level list
.byte 0x80, 0x40, 0, 0xf2, 0x30     # proof Expr.const True.intro
.asciz "intro"
.byte 0xd0, 0xd0                    # level list and mutual declaration list
.byte 0xf0, 0xf0                    # extra constants and entries
.Llgz_end:

.asciz "concatenated.bin"
.byte 0
.quad .Lstream_end-.Lstream
.Lstream:
skip_empty
raw_header 3
.ascii "one"
.long 0x184d2a5f, 5
.byte 0, 0xff, 10, 13, 0
raw_header 0
raw_header 3
.ascii "two"
skip_empty
.Lstream_end:

.asciz "empty-frames.bin"
.byte 0
.quad .Lempty_end-.Lempty
.Lempty:
raw_header 0
skip_empty
raw_header 0
.Lempty_end:

.asciz "skip-only.bin"
.byte 0
.quad 8
skip_empty

.section .ltar_stream_faults,"a",@progbits
.asciz "no-frames.bin"
.byte 0
.quad 0

# Valid initial frame followed by an invalid frame in the same member.
.asciz "short-skip-header.bin"
.byte 0
.quad .Lshort_header_end-.Lshort_header
.Lshort_header:
raw_header 1
.byte 'X'
.long 0x184d2a50
.short 0
.Lshort_header_end:
.asciz "short-skip-body.bin"
.byte 0
.quad .Lshort_skip_end-.Lshort_skip
.Lshort_skip:
raw_header 1
.byte 'X'
.long 0x184d2a51, 8
.byte 1, 2, 3
.Lshort_skip_end:
.asciz "short-frame.bin"
.byte 0
.quad .Lshort_frame_end-.Lshort_frame
.Lshort_frame:
raw_header 1
.byte 'X'
raw_header 4
.ascii "abc"
.Lshort_frame_end:
.asciz "bad-checksum.bin"
.byte 0
.quad .Lbad_checksum_end-.Lbad_checksum
.Lbad_checksum:
raw_header 1
.byte 'X'
.long 0xfd2fb528
.byte 0x24, 1, 9, 0, 0, 'Y'       # last raw block, checksum flag
.long 0                            # wrong XXH64 low word
.Lbad_checksum_end:

# Duplicating only the selected member leaves the directory valid.
.section .ltar_duplicate,"a",@progbits
.asciz "lib/Tiny.olean"
.byte 1
.quad 0
.section .note.GNU-stack,"",@progbits
