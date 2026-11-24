# SPDX-License-Identifier: Apache-2.0
# Raw LGZ2 with saved names, levels and expressions. Each array entry saves
# its result in the next back-reference slot, starting with zero.
.section .lgz_expr_fixture,"a",@progbits
.ascii "LGZ2"
.long 0x12345678
.quad 9760                          # exact decompressed size
.ascii "0000000000000000000000000000000000000000"
.byte 1, 4, 19, 0, 0                # GMP, 4.19.0-rc1
.byte 0, 0xd0+25                    # Array of 25 results
.macro NODE op
    .byte 0x80, 0xff, \op
.endm
.macro REF slot
    .if \slot < 8
        .byte 0xf0+\slot
    .else
        .byte 0xfc, \slot
    .endif
.endm

NODE 0                              # 0: Name.str .anonymous …
.byte 0xd0, 0x30
.asciz "name.component.\316\261"
NODE 1                              # 1: Name.num (small)
REF 0
.byte 0xd0+23
NODE 1                              # 2: Name.num (heap numeral hashes to 17)
REF 1
.byte 0x40, 0xd1
.quad 0xfedcba9876543210
NODE 2                              # 3: Level.succ .zero
.byte 0xd0
NODE 5                              # 4: Level.param
REF 1
NODE 6                              # 5: Level.mvar
REF 0
NODE 3                              # 6: Level.max
REF 4
REF 5
NODE 4                              # 7: Level.imax
REF 6
REF 3
NODE 7                              # 8: Expr.bvar 74565
.byte 0xfa
.long 74565
NODE 8                              # 9: Expr.fvar
REF 1
NODE 9                              # 10: Expr.mvar
REF 0
NODE 10                             # 11: Expr.sort
REF 7
NODE 11                             # 12: Expr.lit (.natVal <heap numeral>)
.byte 0x02, 0x40, 0xd2
.quad 0x9ab876010349efcd, 0x349
NODE 11                             # 13: Expr.lit (.strVal …)
.byte 0x12, 0x30
.asciz "literal string"
NODE 0x40                           # 14: Expr.const with two universe levels
REF 1
.byte 0x14
REF 7
.byte 0x14
REF 5
.byte 0xd0
NODE 0x23                           # 15: three successive applications
REF 9
REF 10
REF 8
REF 14
NODE 0x1b                           # 16: Expr.lam, binderInfo 3
REF 0
REF 11
REF 8
NODE 0x1e                           # 17: Expr.forallE, binderInfo 2
REF 0
REF 10
REF 16
NODE 0x0f                           # 18: Expr.letE, nonDep
REF 0
REF 17
REF 11
REF 8
NODE 13                             # 19: Expr.proj
REF 0
.byte 0x40, 0xd1
.quad 0x783677736cd82034
REF 15
NODE 12                             # 20: Expr.mdata
.byte 0xd0
REF 19
NODE 0x42                           # 21: Expr.const [] with two applications
REF 0
.byte 0xd0
REF 8
REF 20
NODE 12                             # 22: Expr.approxDepth saturates at 255
.byte 0xd0
.rept 256
    .byte 12, 0xd0
.endr
REF 8
NODE 0x18                           # 23: depth 255 still mixes with salt 256
REF 0
REF 22
REF 16
NODE 0x0e                           # 24: Expr.letE, dependent
REF 0
REF 13
REF 23
REF 11
.section .note.GNU-stack,"",@progbits
