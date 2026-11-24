# SPDX-License-Identifier: Apache-2.0
# Standalone ABI checks. Fixed object fixtures and four test runtime entry points
# allow GNU as/ld to exercise spine semantics without a Lean installation.
.intel_syntax noprefix
.data
.balign 8
.macro header rc, fields, tag
    .long \rc
    .short 0
    .byte \fields, \tag
.endm
.Lleaf:    header 0, 1, 0
           .quad 1, 0
.Larg1:    header 0, 1, 0
           .quad 3, 0
.Larg2:    header 0, 1, 0
           .quad 5, 0
.Lapp1:    header 0, 2, 5
           .quad .Lleaf, .Larg1, 0
.Lapp2:    header 0, 2, 5
           .quad .Lapp1, .Larg2, 0
.Lmd:      header 0, 2, 10
           .quad 1, .Lapp2, 0
.Lmd2:     header 0, 2, 10
           .quad 1, .Lmd, 0
.Louter:   header 0, 2, 5
           .quad .Lmd2, .Lapp1, 0
.Lbig:     header 3, 0, 250

.bss
.balign 8
.Larray:       .skip 24 + 2*8
.Ldeep:        .skip 4096*32
.Latomic_inc:  .skip 4
.Lcold_dec:    .skip 4
.Lbig_sub:     .skip 4

.text
.globl _start
.type _start,@function
_start:
    mov ebp, 1
    xor r12d, r12d
.Lnext_tag:
    cmp r12d, 5
    je .Lskip_tag
    cmp r12d, 10
    je .Lskip_tag
    mov byte ptr [rip + .Lleaf + 7], r12b
    lea rdi, [rip + .Lleaf]
    call l_Lean_Expr_getAppFn
    lea rdx, [rip + .Lleaf]
    cmp rax, rdx
    jne .Lfail
    mov rdi, rax
    call l_Lean_Expr_getAppNumArgs_x27
    cmp rax, 1
    jne .Lfail
.Lskip_tag:
    inc r12d
    cmp r12d, 12
    jb .Lnext_tag
    mov byte ptr [rip + .Lleaf + 7], 0

    inc ebp
    lea rdi, [rip + .Louter]
    call l_Lean_Expr_getAppFn
    lea rdx, [rip + .Lmd2]
    cmp rax, rdx
    jne .Lfail
    lea rdi, [rip + .Louter]
    call l_Lean_Expr_getAppFn_x27___boxed
    lea rdx, [rip + .Lleaf]
    cmp rax, rdx
    jne .Lfail
    lea rdi, [rip + .Louter]
    call l_Lean_Expr_getAppNumArgs___boxed
    cmp rax, 3                           # 1 argument up to the metadata
    jne .Lfail
    lea rdi, [rip + .Louter]
    call l_Lean_Expr_getAppNumArgs_x27___boxed
    cmp rax, 7                           # 3 across nested metadata
    jne .Lfail

    inc ebp
    mov dword ptr [rip + .Lapp2], 2
    mov dword ptr [rip + .Lleaf], -1
    lea rdi, [rip + .Lapp2]
    call l_Lean_Expr_getAppFn___boxed
    cmp dword ptr [rip + .Latomic_inc], 1
    jne .Lfail
    cmp dword ptr [rip + .Lleaf], -2
    jne .Lfail
    cmp dword ptr [rip + .Lapp2], 1
    jne .Lfail
    lea rdi, [rip + .Lapp2]
    call l_Lean_Expr_getAppNumArgs___boxed
    cmp dword ptr [rip + .Lcold_dec], 1
    jne .Lfail
    mov dword ptr [rip + .Lapp2], 0
    mov dword ptr [rip + .Lleaf], 0

    inc ebp
    mov edi, 1
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppFn
    lea rdx, [rip + .Lapp2]
    cmp rax, rdx
    jne .Lfail
    mov edi, 3
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppFn___boxed
    lea rdx, [rip + .Lapp1]
    cmp rax, rdx
    jne .Lfail
    lea rdi, [rip + .Lbig]
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppFn
    lea rdx, [rip + .Lleaf]
    cmp rax, rdx
    jne .Lfail
    cmp dword ptr [rip + .Lbig_sub], 1
    jne .Lfail
    cmp dword ptr [rip + .Lbig], 2
    jne .Lfail

    inc ebp
    lea rdi, [rip + .Lapp2]
    call l_Lean_Expr_getAppArgs
    lea rdx, [rip + .Larg1]
    lea rcx, [rip + .Larg2]
    call .Lcheck_two
    lea rdi, [rip + .Lapp2]
    call l_Lean_Expr_getAppRevArgs
    lea rdx, [rip + .Larg2]
    lea rcx, [rip + .Larg1]
    call .Lcheck_two
    lea rdi, [rip + .Lbig]
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppArgs
    lea rdx, [rip + .Larg1]
    lea rcx, [rip + .Larg2]
    call .Lcheck_two
    cmp dword ptr [rip + .Lbig], 1
    jne .Lfail

    inc ebp
    mov edi, 3
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppArgs
    cmp qword ptr [rax + 8], 1
    jne .Lfail
    lea rdx, [rip + .Larg2]
    cmp [rax + 24], rdx
    jne .Lfail
    lea rdi, [rip + .Louter]
    call l_Lean_Expr_getAppArgs
    cmp qword ptr [rax + 8], 1
    jne .Lfail
    lea rdx, [rip + .Lapp1]
    cmp [rax + 24], rdx
    jne .Lfail
    mov edi, 1
    lea rsi, [rip + .Lapp2]
    call l_Lean_Expr_getBoundedAppArgs
    cmp qword ptr [rax + 8], 0
    jne .Lfail

    inc ebp
    lea rdi, [rip + .Ldeep]
    lea rdx, [rip + .Lleaf]
    mov ecx, 4096
.Llink:
    mov byte ptr [rdi + 7], 5
    mov [rdi + 8], rdx
    mov rdx, rdi
    add rdi, 32
    dec ecx
    jnz .Llink
    mov r12, rdx
    mov rdi, r12
    call l_Lean_Expr_getAppNumArgs
    cmp rax, 8193
    jne .Lfail
    mov rdi, r12
    call l_Lean_Expr_getAppFn_x27
    lea rdx, [rip + .Lleaf]
    cmp rax, rdx
    jne .Lfail

    xor edi, edi
    jmp .Lexit
.Lfail:
    mov edi, ebp
.Lexit:
    mov eax, 60
    syscall
.size _start, .-_start

.Lcheck_two:
    cmp qword ptr [rax + 8], 2
    jne .Lfail
    cmp qword ptr [rax + 16], 2
    jne .Lfail
    cmp [rax + 24], rdx
    jne .Lfail
    cmp [rax + 32], rcx
    jne .Lfail
    ret

.globl lean_nat_big_sub
lean_nat_big_sub:
    lea rax, [rip + .Lbig]
    cmp rdi, rax
    jne .Lfail
    cmp rsi, 3
    jne .Lfail
    inc dword ptr [rip + .Lbig_sub]
    mov rax, -1                          # model 2^63 - 1 becoming immediate
    ret
.globl lean_inc_ref_cold
lean_inc_ref_cold:
    inc dword ptr [rip + .Latomic_inc]
    dec dword ptr [rdi]                  # MT increment increases magnitude
    ret
.globl lean_dec_ref_cold
lean_dec_ref_cold:
    inc dword ptr [rip + .Lcold_dec]
    ret
.globl lean_mk_array
lean_mk_array:
    cmp rsi, 1
    jne .Lfail
    test dil, 1
    jz .Lfail
    shr rdi, 1
    cmp rdi, 2
    ja .Lfail
    lea rax, [rip + .Larray]
    mov [rax + 8], rdi
    mov [rax + 16], rdi
    mov [rax + 24], rsi
    mov [rax + 32], rsi
    ret

.section .note.GNU-stack,"",@progbits
