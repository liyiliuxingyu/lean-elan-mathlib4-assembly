# SPDX-License-Identifier: Apache-2.0
# Extract named sections with objcopy -O binary -j SECTION.
.intel_syntax noprefix
.section .ltar_v1,"a",@progbits
.ascii "LTAR"
.quad 17
.asciz "t"
.byte 0
.asciz "legacy"
.asciz "a"
.byte 2
.quad -1

.section .ltar_v2,"a",@progbits
.ascii "LTR2"
.quad 42
.asciz "x.trace"
.byte 3
.quad 42
.byte 0
.asciz "first"
.asciz "x.olean"
.byte 1
.quad 3
.byte 0, 1, 0xff                 # opaque compressed member
.asciz "a\tb\\c"
.byte 0
.quad 2
.byte 17, 34
.byte 0
.asciz ""
.byte 0
.asciz "末行"

.section .ltar_comments_v1,"a",@progbits
.ascii "legacy\n"
.section .ltar_list_v1,"a",@progbits
.ascii "header-hash\t4\t8\tt\nhash-plain\t25\t8\ta\n"
.section .ltar_comments_v2,"a",@progbits
.ascii "first\n\n末行\n"
.section .ltar_list_v2,"a",@progbits
.ascii "hash-json\t21\t8\tx.trace\nlgz\t53\t3\tx.olean\nzstd\t71\t2\ta\\x09b\\x5cc\n"

# A valid comment followed by a malformed size. A failed check must not
# leave a partial comment or listing on standard output.
.section .ltar_bad_size,"a",@progbits
.ascii "LTAR"
.quad 0
.asciz "t"
.byte 0
.asciz "before malformed entry"
.asciz "entry"
.byte 0
.quad -1
.section .ltar_bad_text,"a",@progbits
.ascii "LTAR"
.quad 0
.asciz "t"
.byte 0, 0xed, 0xa0, 0x80, 0     # invalid UTF-8 surrogate
.section .ltar_no_nul,"a",@progbits
.ascii "LTAR"
.quad 0
.ascii "trace"
.section .ltar_bad_tag,"a",@progbits
.ascii "LTR2"
.quad 0
.asciz "t"
.byte 4
.quad 0
.section .note.GNU-stack,"",@progbits
