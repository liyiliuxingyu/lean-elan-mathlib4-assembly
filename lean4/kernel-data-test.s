# SPDX-License-Identifier: Apache-2.0
# Standalone x86-64 regression tests for the exported Expr and Level accessors.
.intel_syntax noprefix
.section .rodata
.Lexpr_fields:  .byte 1,1,1,1,2,2,3,3,4,1,2,3
.Llevel_fields: .byte 0,1,2,2,1,1

.bss
.balign 8
.Lobject:       .skip 64
.Lcold_count:   .skip 4
.Lheartbeat:    .skip 4

.text
.macro check fn, expected
    mov rdi, r12
    call \fn
    cmp rax, \expected
    jne .Lfail
.endm

.globl _start
.type _start, @function
_start:
    lea r12, [rip + .Lobject]
    xor r13d, r13d                         # Expr tag
.Lexpr_tag:
    mov [r12 + 7], r13b
    lea rax, [rip + .Lexpr_fields]
    movzx eax, byte ptr [rax + r13]
    mov [r12 + 6], al
    lea rbp, [r12 + rax*8 + 8]            # constructor's scalar area
    xor r14d, r14d                         # all 16 flag combinations
.Lexpr_flags:
    mov rax, r14
    shl rax, 40
    movabs rdx, 0xabcde0feffff0001        # max-width fields, nonzero depth
    or rax, rdx
    mov [rbp], rax
    mov eax, r13d
    and eax, -2
    xor ebx, ebx
    cmp eax, 6
    jne .Lfields_ready
    mov ebx, r14d
    and ebx, 3
    mov [rbp + 8], bl
.Lfields_ready:
    mov dword ptr [r12], 10
    mov r15d, 0xffff0001
    check lean_expr_hash, r15
    mov r15d, r14d
    and r15d, 1
    check lean_expr_has_fvar, r15
    mov r15d, r14d
    shr r15d, 1
    and r15d, 1
    check lean_expr_has_expr_mvar, r15
    mov r15d, r14d
    shr r15d, 2
    and r15d, 1
    check lean_expr_has_level_mvar, r15
    xor r15d, r15d
    test r14d, 6
    setne r15b
    check lean_expr_has_mvar, r15
    mov r15d, r14d
    shr r15d, 3
    check lean_expr_has_level_param, r15
    check lean_expr_loose_bvar_range, 0xabcde
    check lean_expr_binder_info, rbx
    cmp dword ptr [r12], 2
    jne .Lfail
    inc r14d
    cmp r14d, 16
    jb .Lexpr_flags
    inc r13d
    cmp r13d, 12
    jb .Lexpr_tag

    mov r12d, 1                            # Level.zero
    check lean_level_hash, 2221
    check lean_level_has_mvar, 0
    check lean_level_has_param, 0
    check lean_level_depth, 0
    cmp dword ptr [rip + .Lheartbeat], 0
    jne .Lfail

    lea r12, [rip + .Lobject]
    mov r13d, 1
.Llevel_tag:
    mov [r12 + 7], r13b
    lea rax, [rip + .Llevel_fields]
    movzx eax, byte ptr [rax + r13]
    mov [r12 + 6], al
    lea rbp, [r12 + rax*8 + 8]
    xor r14d, r14d                         # both level flags
.Llevel_flags:
    mov rax, r14
    shl rax, 32
    movabs rdx, 0xfffffe00abcd0123
    or rax, rdx
    mov [rbp], rax
    mov dword ptr [r12], 5
    mov r15d, 0xabcd0123
    check lean_level_hash, r15
    mov r15d, r14d
    and r15d, 1
    check lean_level_has_mvar, r15
    mov r15d, r14d
    shr r15d, 1
    check lean_level_has_param, r15
    check lean_level_depth, 0xfffffe
    cmp dword ptr [r12], 1
    jne .Lfail
    inc r14d
    cmp r14d, 4
    jb .Llevel_flags
    inc r13d
    cmp r13d, 6
    jb .Llevel_tag
    cmp dword ptr [rip + .Lheartbeat], 80
    jne .Lfail

    # Persistent, exclusive, and multi-thread counts must reach the proper path.
    mov r15d, 0xabcd0123
    mov dword ptr [r12], 0
    check lean_expr_hash, r15
    cmp dword ptr [rip + .Lcold_count], 0
    jne .Lfail
    mov dword ptr [r12], 1
    check lean_expr_hash, r15
    mov dword ptr [r12], -2
    check lean_level_hash, r15
    cmp dword ptr [rip + .Lcold_count], 2
    jne .Lfail
    xor edi, edi
    jmp .Lexit
.Lfail:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall
.size _start, . - _start

# Test doubles for dependencies supplied by the Lean runtime in applications.
.globl lean_inc_heartbeat
.type lean_inc_heartbeat, @function
lean_inc_heartbeat:
    inc dword ptr [rip + .Lheartbeat]
    jmp .Lclobber
.size lean_inc_heartbeat, . - lean_inc_heartbeat
.globl lean_dec_ref_cold
.type lean_dec_ref_cold, @function
lean_dec_ref_cold:
    cmp rdi, r12
    jne .Lfail
    inc dword ptr [rip + .Lcold_count]
.Lclobber:
    mov rax, rsp
    and eax, 15
    cmp eax, 8
    jne .Lfail
    mov eax, 0xdead1234
    xor edi, edi
    xor ecx, ecx
    ret
.size lean_dec_ref_cold, . - lean_dec_ref_cold
.section .note.GNU-stack,"",@progbits
