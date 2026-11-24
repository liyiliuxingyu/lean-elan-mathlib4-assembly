# SPDX-License-Identifier: Apache-2.0
# Normal-mode features and legacy headers. Tests compare with official leantar.
.section .lgz_v0,"a",@progbits
.ascii "LGZ!"
.long 0xabcd0123
.quad 32
.byte 0xd7                         # root is boxed 7

.section .lgz_v1,"a",@progbits
.ascii "LGZ1"
.long 0x12ae
.quad 104
.ascii "0123456789abcdef0123456789abcdef01234567"
.byte 0x30
.asciz "legacy"

.section .lgz_normal,"a",@progbits
.globl lgz_normal_start,lgz_normal_end
lgz_normal_start:
.ascii "LGZ2"
.long 0x6789
.quad 768
.ascii "0123456789abcdef0123456789abcdef01234567"
.byte 0, 0                         # portable MPZ, raw version string
.Lversion:
.asciz "4.19.custom+portable"
.zero 33-(.-.Lversion)
.byte 0x00,0xd0+21                 # Array of 21 values
.byte 0xff,0xff,0x30               # two SAVE slots hold the same object
.asciz "snow \342\230\203"
.byte 0xf0
.byte 0xfc,1
.byte 0xfd
.short 0
.byte 0xfe
.long 1
.byte 0xf8,-4                      # sign-extended boxed values of all widths
.byte 0xf9
.short -4097
.byte 0xfa
.long -123456
.byte 0xfb
.quad 0xf0123456789abcde
.byte 0x20,0xd5                    # scalar array with three padding bytes
.ascii "bytes"
.byte 0x10,39,1                    # big constructor, pointer then raw scalars
.short 2
.byte 0xf1
.quad 0x0123456789abcdef,0x4243
.byte 0x90,0xd5                    # promise
.byte 0x60,0xd6                    # task
.byte 0x50,0xd7                    # thunk
.byte 0x70,0xd8                    # ref
.byte 0x40,0xd2                    # portable limbs; last u32 word zero
.quad 0xff12345678100220,0x108
.byte 0x40,0xd1                    # both u32 words present
.quad 0xdc0310207cb86432
.byte 0x00,0xd0                    # empty pointer array
.byte 0x20,0xd0                    # empty scalar array
.byte 0x30,0                       # empty string
.byte 0x80,0x20,0x73               # mode switch, packed ctor with one scalar
.byte 0xf8,99
.quad 0x1122334455667788
lgz_normal_end:

.section .lgz_deep,"a",@progbits
.ascii "LGZ!"
.long 0
.quad 800032
.rept 50000
.byte 0x02                         # unary constructor
.endr
.byte 0xd0

.section .lgz_wide,"a",@progbits
.ascii "LGZ!"
.long 0x1020304
.quad 524384
.byte 0x00,0xfa
.long 65541                        # 65537 slots and four different backrefs
.set slot,0
.rept 65537
    .byte 0xff,0xd0+(slot%32)
    .set slot,slot+1
.endr
.byte 0xf7
.byte 0xfc,255
.byte 0xfd
.short 385
.byte 0xfe
.long 65536

.section .note.GNU-stack,"",@progbits
