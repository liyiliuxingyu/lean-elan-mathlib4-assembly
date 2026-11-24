# SPDX-License-Identifier: Apache-2.0
# Test driver for the compiler-emitted Nat.pair and Nat.unpair from the
# two official .ltar files. Stdin contains canonical decimal triples A B N.
.intel_syntax noprefix
.section .rodata
.scan: .asciz "%ms %ms %ms"
.success: .asciz "%ld published Mathlib function comparisons passed\n"
.failure: .asciz "published Mathlib comparison failed at triple %ld\n"
.text
.globl main
.type main,@function
main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
    call lean_initialize_runtime_module@PLT
    call lean_io_mark_end_initialization@PLT
    xor ebx, ebx
.next:
    lea rdi, [rip+.scan]
    mov rsi, rsp
    lea rdx, [rsp+8]
    lea rcx, [rsp+16]
    xor eax, eax
    call scanf@PLT
    cmp eax, -1
    je .done
    inc rbx
    cmp eax, 3
    jne .bad
    mov rdi, [rsp]
    call lean_cstr_to_nat@PLT
    mov r12, rax
    mov rdi, [rsp+8]
    call lean_cstr_to_nat@PLT
    mov r13, rax
    mov rdi, [rsp+16]
    call lean_cstr_to_nat@PLT
    mov r14, rax
    mov rdi, [rsp]
    call free@PLT
    mov rdi, [rsp+8]
    call free@PLT
    mov rdi, [rsp+16]
    call free@PLT
    mov rdi, r12
    mov rsi, r13
    call l_Nat_pair
    mov r15, rax
    mov rdi, rax
    mov rsi, r14
    call .nat_eq
    test al, al
    jz .bad
    mov rdi, r15
    call .dec
    mov rdi, r14
    call l_Nat_unpair
    mov r15, rax
    mov rdi, [r15+8]             # Prod.fst
    mov rsi, r12
    call .nat_eq
    test al, al
    jz .bad
    mov rdi, [r15+16]            # Prod.snd
    mov rsi, r13
    call .nat_eq
    test al, al
    jz .bad
    mov rdi, r15
    call .dec
    mov rdi, r14
    call .dec
    mov rdi, r13
    call .dec
    mov rdi, r12
    call .dec
    jmp .next
.done:
    test rbx, rbx
    jz .bad
    lea rdi, [rip+.success]
    lea rsi, [rbx+rbx]
    xor eax, eax
    call printf@PLT
    xor eax, eax
    jmp .return
.bad:
    lea rdi, [rip+.failure]
    mov rsi, rbx
    xor eax, eax
    call printf@PLT
    mov eax, 1
.return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Tagged Lean naturals are normalized. Big numbers use the runtime equality.
.nat_eq:
    cmp rdi, rsi
    sete al
    je .ret
    test dil, 1
    jnz .ret
    test sil, 1
    jnz .ret
    jmp lean_nat_big_eq@PLT
.ret:
    ret
.dec:
    test dil, 1
    jnz .ret
    mov eax, [rdi]
    test eax, eax
    jz .ret
    cmp eax, 1
    jle lean_dec_ref_cold@PLT
    dec dword ptr [rdi]
    ret
.section .note.GNU-stack,"",@progbits
