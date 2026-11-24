.intel_syntax noprefix
.include "proof_format.inc"

.macro string name, content
\name:
    .ascii "\content"
.equ \name\()_length, . - \name
.endm

.macro write_text name
    lea rsi, [rip + \name]
    mov edx, \name\()_length
    call .Lwrite_all
.endm

.section .rodata
string declaration, "theorem asm_nat_succ_injective {x y : Nat} (h : Nat.succ x = Nat.succ y) : x = y :=\n  "
string pred, "(congrArg Nat.pred "
string succ, "(congrArg Nat.succ "
string symm, "(Eq.symm "
string hypothesis, "h"
string close, ")"
string newline, "\n"

.text
.globl _start
.type _start, @function
_start:
    lea r12, [rip + mathlib_nat_succ_injective]
    lea r13, [rip + mathlib_nat_succ_injective_end]
    mov rdi, r12
    mov rsi, r13
    sub rsi, r12
    call mathlib_verify_nat_certificate
    test eax, eax
    jz .Lfailure

    # The printer names this specific proposition. Check its header before writing it.
    cmp dword ptr [r12 + ML_VARIABLE_COUNT], 2
    jne .Lfailure
    cmp dword ptr [r12 + ML_HYPOTHESIS_LEFT], ML_SUCC_STEP + 1
    jne .Lfailure
    cmp dword ptr [r12 + ML_HYPOTHESIS_RIGHT], ML_SUCC_STEP + 2
    jne .Lfailure
    cmp dword ptr [r12 + ML_GOAL_LEFT], 1
    jne .Lfailure
    cmp dword ptr [r12 + ML_GOAL_RIGHT], 2
    jne .Lfailure
    write_text declaration

    # The final instruction is the outermost Lean term constructor.
    lea r14, [r12 + ML_HEADER_SIZE + 1]
    xor r15d, r15d
.Lwrite_prefixes:
    cmp r13, r14
    je .Lwrite_hypothesis
    dec r13
    inc r15
    movzx eax, byte ptr [r13]
    cmp eax, ML_CONGR_PRED
    je .Lwrite_pred
    cmp eax, ML_CONGR_SUCC
    je .Lwrite_succ
    cmp eax, ML_SYMMETRY
    jne .Lfailure
    write_text symm
    jmp .Lwrite_prefixes
.Lwrite_pred:
    write_text pred
    jmp .Lwrite_prefixes
.Lwrite_succ:
    write_text succ
    jmp .Lwrite_prefixes

.Lwrite_hypothesis:
    write_text hypothesis
.Lwrite_suffixes:
    test r15, r15
    jz .Lfinish
    write_text close
    dec r15
    jmp .Lwrite_suffixes
.Lfinish:
    write_text newline
    xor edi, edi
    jmp .Lexit
.Lfailure:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall
.size _start, .-_start

# Linux write(2). Preserve the printer's state in r12-r15.
.Lwrite_all:
    mov eax, 1
    mov edi, 1
    syscall
    cmp rax, -4                       # EINTR
    je .Lwrite_all
    test rax, rax
    jle .Lfailure
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite_all
    ret

.section .note.GNU-stack,"",@progbits
