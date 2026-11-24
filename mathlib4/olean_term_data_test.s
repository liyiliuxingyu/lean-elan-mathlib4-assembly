# SPDX-License-Identifier: Apache-2.0
# Assembly-only regression cases for compact GMP and TSV-safe formatting.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ PREFERRED, 0x635180000000

.macro LEAN_STRING start, bytes
    .balign 8
\start:
    .long 0
    .word 1
    .byte 0, 249
    .quad 1f - 0f, 1f - 0f, 1f - 0f - 1
0:  .asciz "\bytes"
1:
.endm

.section .rodata
.balign 8
.Limage:
    .space 96
LEAN_STRING .Ldotted, "n.a"
.balign 8
.Lcontrol:
    .long 0
    .word 1
    .byte 0, 249
    .quad 6, 6, 5
    .byte 'a', 9, 'b', 92, 34, 0
.balign 8
.Lmpz:
    .long 0
    .word 40
    .byte 0, 250
    .long 2, 2
    .quad PREFERRED + .Lmpz_digits - .Limage
.Lmpz_digits:
    .quad 1, 1                      # 2^64 + 1
.Lfirst_name:
    .long 0
    .word 32
    .byte 2, 1
    .quad 1, PREFERRED + .Ldotted - .Limage, 0
.Lnumeric_name:
    .long 0
    .word 32
    .byte 2, 2
    .quad PREFERRED + .Lfirst_name - .Limage
    .quad PREFERRED + .Lmpz - .Limage, 0
.Lsuccessor:
    .long 0
    .word 24
    .byte 1, 1
    .quad 1, 0
.Lparam:
    .long 0
    .word 24
    .byte 1, 4
    .quad PREFERRED + .Lfirst_name - .Limage, 0
.Limax:
    .long 0
    .word 32
    .byte 2, 3
    .quad PREFERRED + .Lsuccessor - .Limage
    .quad PREFERRED + .Lparam - .Limage, 0
.Limage_end:

.balign 8
.Lview:
    .quad .Limage, .Limage_end - .Limage, PREFERRED
    .zero VIEW_BYTES - 24

.Ldecimal:
    .asciz "18446744073709551617"
.Ldecimal_end:
.Lsmall:
    .asciz "9223372036854775807"
.Lsmall_end:
.Lname:
    .byte 0xc2, 0xab
    .ascii "n.a"
    .byte 0xc2, 0xbb
    .asciz ".18446744073709551617"
.Lname_end:
.Lliteral:
    .byte 34
    .ascii "a\\x09b\\x5c\\x22"
    .byte 34, 0
.Lliteral_end:

.balign 8
.Lformats:
    .quad mathlib_olean_nat_format, PREFERRED + .Lmpz - .Limage
    .quad .Ldecimal, .Ldecimal_end - .Ldecimal
    .quad mathlib_olean_nat_format, -1
    .quad .Lsmall, .Lsmall_end - .Lsmall
    .quad mathlib_olean_name_format, PREFERRED + .Lnumeric_name - .Limage
    .quad .Lname, .Lname_end - .Lname
    .quad mathlib_olean_string_format, PREFERRED + .Lcontrol - .Limage
    .quad .Lliteral, .Lliteral_end - .Lliteral
.Lformats_end:
.Llevels:
    .quad 1, 0, 0, 0, 0
    .quad .Lsuccessor - .Limage, 1, 1, 0, 0
    .quad .Lparam - .Limage, 4, PREFERRED + .Lfirst_name - .Limage, 0, 0
    .quad .Limax - .Limage, 3, .Lsuccessor - .Limage, .Lparam - .Limage, 0
.Llevels_end:

.bss
.balign 8
.Loutput:
    .zero 128

.text
.globl _start
.type _start, @function
_start:
    lea r12, [rip + .Lformats]
    lea r13, [rip + .Lformats_end]
    lea r14, [rip + .Loutput]
    mov ebx, 1

.Lformat_case:
    lea rdi, [rip + .Lview]
    mov rsi, [r12 + 8]
    mov rdx, r14
    mov rcx, [r12 + 24]
    call [r12]
    mov rcx, [r12 + 24]
    inc eax
    cmp eax, ecx
    jne .Lfailed
    mov rdi, r14
    mov rsi, [r12 + 16]
    repe cmpsb
    jne .Lfailed
    inc ebx
    lea rdi, [rip + .Lview]
    mov rsi, [r12 + 8]
    mov rdx, r14
    mov rcx, [r12 + 24]
    dec rcx                         # No room for the final NUL
    call [r12]
    cmp eax, -1
    jne .Lfailed
    inc ebx
    add r12, 32
    cmp r12, r13
    jne .Lformat_case

    lea r12, [rip + .Llevels]
    lea r13, [rip + .Llevels_end]
.Llevel_case:
    lea rdi, [rip + .Lview]
    mov rsi, [r12]
    mov rdx, r14
    call mathlib_olean_level_node
    cmp eax, 1
    jne .Lfailed
    mov rdi, r14
    lea rsi, [r12 + 8]
    mov ecx, 4
    repe cmpsq
    jne .Lfailed
    inc ebx
    add r12, 40
    cmp r12, r13
    jne .Llevel_case

    xor ebx, ebx
.Lfailed:
    mov edi, ebx
    mov eax, 60
    syscall
.size _start, .-_start
.section .note.GNU-stack,"",@progbits
