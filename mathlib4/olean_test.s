# SPDX-License-Identifier: Apache-2.0
# Pinned-format regression image. Stored pointers intentionally differ
# from the in-process addresses of these test objects.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ preferred_base, 0x123450000

.macro file_pointer target
    .quad preferred_base + (\target - .Limage)
.endm

.macro frozen_header tag, fields, size
    .long 0
    .word \size
    .byte \fields, \tag
.endm

.macro frozen_string label, value
    .balign 8
\label:
    frozen_header 249, 0, 1
    .quad \label\()_end - \label\()_text
    .quad \label\()_end - \label\()_text
    .quad \label\()_end - \label\()_text - 1
\label\()_text:
    .asciz "\value"
\label\()_end:
.endm

.macro string_name label, prefix, text
    .balign 8
\label:
    frozen_header 1, 2, 32
    .ifb \prefix
        .quad 1
    .else
        file_pointer \prefix
    .endif
    file_pointer \text
    .quad 0
.endm

.section .data
.balign 8
.Limage:
    .ascii "olean"
    .byte 2, 1
    .ascii "4.19.0"
    .zero 27
    .ascii "6caaee842e9495688c1567e78c0e68dbb96942aa"
    .quad preferred_base
    file_pointer .Lmodule

.Lmodule:
    frozen_header 0, 5, 48
    file_pointer .Lempty_array
    file_pointer .Lnames
    file_pointer .Lconstants
    file_pointer .Lempty_array
    file_pointer .Lempty_array

.Lempty_array:
    frozen_header 246, 0, 1
    .quad 0, 0

.Lnames:
    frozen_header 246, 0, 1
    .quad 3, 3
    file_pointer .Lname_succ
    file_pointer .Lname_num
    file_pointer .Lname_dot

.Lconstants:
    frozen_header 246, 0, 1
    .quad 3, 3
    file_pointer .Ltheorem
    file_pointer .Ldefinition
    file_pointer .Ldefinition

    frozen_string .Lstring_nat, Nat
    frozen_string .Lstring_succ, succ_injective
    frozen_string .Lstring_worker, worker
    frozen_string .Lstring_dot, has.dot
    string_name .Lname_nat, , .Lstring_nat
    string_name .Lname_succ, .Lname_nat, .Lstring_succ
    string_name .Lname_worker, .Lname_nat, .Lstring_worker
    string_name .Lname_dot, .Lname_nat, .Lstring_dot
.Lname_num:
    frozen_header 2, 2, 32
    file_pointer .Lname_worker
    .quad 35                      # Lean-immediate representation of 17.
    .quad 0

.Ltheorem:
    frozen_header 2, 1, 16
    file_pointer .Ltheorem_val
.Ltheorem_val:
    frozen_header 0, 3, 32
    file_pointer .Lconstant_val
    file_pointer .Lproof_expr
    .quad 1
.Lconstant_val:
    frozen_header 0, 3, 32
    file_pointer .Lname_succ
    .quad 1
    file_pointer .Ltype_expr
.Ltype_expr:
    frozen_header 3, 1, 16        # Expr.sort
    .quad 1
.Lproof_expr:
    frozen_header 4, 2, 24        # Expr.const
    file_pointer .Lname_nat
    .quad 1
.Ldefinition:
    frozen_header 1, 1, 16
    file_pointer .Lconstant_val
.Limage_end:
.equ fixture_size, .Limage_end - .Limage

.section .rodata
.Lsucc_query:      .asciz "Nat.succ_injective"
.Lwrong_case:      .asciz "nat.succ_injective"
.Lwrong_prefix:    .asciz "Int.succ_injective"
.Lleaf_only:       .asciz "succ_injective"
.Lextra_prefix:    .asciz "Other.Nat.succ_injective"
.Lnumeric_query:   .asciz "Nat.worker.17"
.Lwrong_number:    .asciz "Nat.worker.18"
.Lquoted_query:    .asciz "Nat.\302\253has.dot\302\273"
.Lunquoted_query:  .asciz "Nat.has.dot"
.Lquoted_number:   .asciz "Nat.worker.\302\25317\302\273"
.Lopen_quote:      .asciz "Nat.\302\253has.dot"
.Lnone:            .asciz ""
.Ltrailing_dot:    .asciz "Nat."
.Ldouble_dot:      .asciz "Nat..worker"
.Lbad_control:     .asciz "Nat.\tworker"
.Loverflow_number: .asciz "Nat.worker.9223372036854775808"

.bss
.balign 8
.Lview:    .zero VIEW_BYTES
.Lresult:  .zero RESULT_BYTES

.macro parse expected, size=fixture_size
    inc r12d
    lea rdi, [rip + .Limage]
    mov esi, \size
    lea rdx, [rip + .Lview]
    call mathlib_olean_parse
    cmp eax, \expected
    jne .Lfailed
.endm

.macro lookup name, expected
    inc r12d
    lea rdi, [rip + .Lview]
    lea rsi, [rip + \name]
    lea rdx, [rip + .Lresult]
    call mathlib_olean_lookup
    cmp eax, \expected
    jne .Lfailed
.endm

.text
.globl _start
.type _start, @function
_start:
    xor r12d, r12d

    parse 0, 95
    xor BYTE PTR [rip + .Limage], 1
    parse 0
    xor BYTE PTR [rip + .Limage], 1
    xor BYTE PTR [rip + .Limage + 5], 1
    parse 0
    xor BYTE PTR [rip + .Limage + 5], 1
    xor BYTE PTR [rip + .Limage + 6], 1
    parse 0
    xor BYTE PTR [rip + .Limage + 6], 1
    xor BYTE PTR [rip + .Limage + 79], 1
    parse 0
    xor BYTE PTR [rip + .Limage + 79], 1
    xor QWORD PTR [rip + .Limage + 88], 1
    parse 0
    xor QWORD PTR [rip + .Limage + 88], 1
    xor BYTE PTR [rip + .Lmodule + 6], 1
    parse 0
    xor BYTE PTR [rip + .Lmodule + 6], 1
    xor BYTE PTR [rip + .Lnames + 7], 1
    parse 0
    xor BYTE PTR [rip + .Lnames + 7], 1
    inc QWORD PTR [rip + .Lnames + 8]
    parse 0
    dec QWORD PTR [rip + .Lnames + 8]
    dec QWORD PTR [rip + .Lconstants + 8]
    parse 0
    inc QWORD PTR [rip + .Lconstants + 8]
    parse 1
    cmp QWORD PTR [rip + .Lview + VIEW_COUNT], 3
    jne .Lfailed
    cmp QWORD PTR [rip + .Lview + VIEW_IMPORTS], 0
    jne .Lfailed

    lookup .Lsucc_query, 1
    cmp QWORD PTR [rip + .Lresult + RESULT_KIND], 2
    jne .Lfailed
    cmp QWORD PTR [rip + .Lresult + RESULT_RECORD], .Ltheorem - .Limage
    jne .Lfailed
    cmp QWORD PTR [rip + .Lresult + RESULT_TYPE], .Ltype_expr - .Limage
    jne .Lfailed
    cmp QWORD PTR [rip + .Lresult + RESULT_PROOF], .Lproof_expr - .Limage
    jne .Lfailed
    lookup .Lwrong_case, 0
    lookup .Lwrong_prefix, 0
    lookup .Lleaf_only, 0
    lookup .Lextra_prefix, 0

    lookup .Lnumeric_query, 1
    cmp QWORD PTR [rip + .Lresult + RESULT_KIND], 1
    jne .Lfailed
    lookup .Lwrong_number, 0
    lookup .Lquoted_number, 0
    lookup .Lquoted_query, 1
    lookup .Lunquoted_query, 0
    lookup .Lopen_quote, -1
    lookup .Lnone, -1
    lookup .Ltrailing_dot, -1
    lookup .Ldouble_dot, -1
    lookup .Lbad_control, -1
    lookup .Loverflow_number, -1

    xor QWORD PTR [rip + .Lname_succ + 16], 1
    lookup .Lsucc_query, -2
    xor QWORD PTR [rip + .Lname_succ + 16], 1
    xor QWORD PTR [rip + .Ltheorem_val + 16], 1
    lookup .Lsucc_query, -2
    xor QWORD PTR [rip + .Ltheorem_val + 16], 1
    lookup .Lsucc_query, 1

    xor edi, edi
    jmp .Lexit
.Lfailed:
    mov edi, r12d
.Lexit:
    mov eax, 60
    syscall
.size _start, . - _start

.section .note.GNU-stack,"",@progbits
