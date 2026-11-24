.intel_syntax noprefix
.include "proof_format.inc"

.macro apply_pred term
    test \term, ML_SUCC_MASK
    jnz .Lpred_cancel_succ\@
    test \term, ML_VARIABLE_MASK
    jz .Lpred_done\@
    mov eax, \term
    and eax, ML_PRED_MASK
    cmp eax, ML_PRED_MASK
    je .Lreject
    add \term, ML_PRED_STEP
    jmp .Lpred_done\@
.Lpred_cancel_succ\@:
    sub \term, ML_SUCC_STEP
.Lpred_done\@:
.endm

.macro apply_succ term
    mov eax, \term
    and eax, ML_SUCC_MASK
    cmp eax, ML_SUCC_MASK
    je .Lreject
    add \term, ML_SUCC_STEP
.endm

.text
.globl mathlib_verify_nat_certificate
.type mathlib_verify_nat_certificate, @function
# rdi = readable certificate bytes, rsi = byte length. Return eax = 1 if valid.
mathlib_verify_nat_certificate:
    test rdi, rdi
    jz .Lreject
    cmp rsi, ML_HEADER_SIZE + 1
    jb .Lreject
    cmp byte ptr [rdi + ML_HEADER_SIZE], ML_ASSUME
    jne .Lreject

    mov r9d, dword ptr [rdi + ML_VARIABLE_COUNT]
    cmp r9d, ML_VARIABLE_MASK
    ja .Lreject
    lea r10, [rdi + ML_HYPOTHESIS_LEFT]
    lea r11, [rdi + ML_HEADER_SIZE]
.Lvalidate_terms:
    mov eax, dword ptr [r10]
    and eax, ML_VARIABLE_MASK
    cmp eax, r9d
    ja .Lreject
    test eax, eax
    jnz .Lnext_term
    test dword ptr [r10], ML_PRED_MASK
    jnz .Lreject
.Lnext_term:
    add r10, 4
    cmp r10, r11
    jne .Lvalidate_terms

    mov r8d, dword ptr [rdi + ML_HYPOTHESIS_LEFT]
    mov r9d, dword ptr [rdi + ML_HYPOTHESIS_RIGHT]
    mov edx, dword ptr [rdi + ML_GOAL_LEFT]
    mov ecx, dword ptr [rdi + ML_GOAL_RIGHT]
    add rdi, ML_HEADER_SIZE + 1
    sub rsi, ML_HEADER_SIZE + 1

.Lnext_instruction:
    test rsi, rsi
    jz .Lcompare_goal
    movzx eax, byte ptr [rdi]
    inc rdi
    dec rsi
    cmp eax, ML_CONGR_PRED
    je .Lcongr_pred
    cmp eax, ML_CONGR_SUCC
    je .Lcongr_succ
    cmp eax, ML_SYMMETRY
    jne .Lreject
    xchg r8d, r9d
    jmp .Lnext_instruction

.Lcongr_pred:
    apply_pred r8d
    apply_pred r9d
    jmp .Lnext_instruction

.Lcongr_succ:
    apply_succ r8d
    apply_succ r9d
    jmp .Lnext_instruction

.Lcompare_goal:
    cmp r8d, edx
    jne .Lreject
    cmp r9d, ecx
    jne .Lreject
    mov eax, 1
    ret
.Lreject:
    xor eax, eax
    ret
.size mathlib_verify_nat_certificate, .-mathlib_verify_nat_certificate

.section .note.GNU-stack,"",@progbits
