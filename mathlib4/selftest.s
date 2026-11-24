.intel_syntax noprefix
.include "proof_format.inc"

.macro certificate name, variables, lhs, rhs, goal_lhs, goal_rhs, instructions:vararg
\name:
    .long \variables, \lhs, \rhs, \goal_lhs, \goal_rhs
    .byte \instructions
\name\()_end:
.endm

.macro check name, expected, length=0
    inc r12d
    lea rdi, [rip + \name]
    .if \length
        mov esi, \length
    .else
        lea rsi, [rip + \name\()_end]
        sub rsi, rdi
    .endif
    call mathlib_verify_nat_certificate
    cmp eax, \expected
    jne .Lfailure
.endm

.section .rodata
certificate reverse, 2, 0x101, 0x102, 2, 1, ML_ASSUME, ML_CONGR_PRED, ML_SYMMETRY
certificate extra_assume, 2, 1, 2, 1, 2, ML_ASSUME, ML_ASSUME
certificate bad_opcode, 2, 1, 2, 1, 2, ML_ASSUME, 0xff
certificate wrong_goal, 2, 0x101, 0x102, 1, 1, ML_ASSUME, ML_CONGR_PRED
certificate bad_variable, 2, 3, 2, 3, 2, ML_ASSUME
certificate bad_variable_count, 256, 1, 2, 1, 2, ML_ASSUME
certificate bad_zero, 0, ML_PRED_STEP, 0, 0, 0, ML_ASSUME
certificate overflow_succ, 1, ML_SUCC_MASK + 1, 1, 1, 1, ML_ASSUME, ML_CONGR_SUCC
certificate overflow_pred, 1, ML_PRED_MASK + 1, 1, 1, 1, ML_ASSUME, ML_CONGR_PRED
certificate pred_zero, 0, 0, 0, 0, 0, ML_ASSUME, ML_CONGR_PRED
certificate pred_variable, 1, 1, 1, ML_PRED_STEP + 1, ML_PRED_STEP + 1, ML_ASSUME, ML_CONGR_PRED
certificate successor, 2, 1, 2, 0x101, 0x102, ML_ASSUME, ML_CONGR_SUCC
certificate missing_assume, 2, 0x101, 0x102, 1, 2, ML_CONGR_PRED

.text
.globl _start
.type _start, @function
_start:
    xor r12d, r12d
    check mathlib_nat_succ_injective, 1
    check mathlib_nat_succ_injective, 0, ML_HEADER_SIZE
    check mathlib_nat_succ_injective, 0, ML_HEADER_SIZE + 1
    check reverse, 1
    check extra_assume, 0
    check bad_opcode, 0
    check wrong_goal, 0
    check bad_variable, 0
    check bad_variable_count, 0
    check bad_zero, 0
    check overflow_succ, 0
    check overflow_pred, 0
    check pred_zero, 1
    check pred_variable, 1
    check successor, 1
    check missing_assume, 0

    xor edi, edi
    jmp .Lexit
.Lfailure:
    mov edi, r12d
.Lexit:
    mov eax, 60
    syscall
.size _start, .-_start

.section .note.GNU-stack,"",@progbits
