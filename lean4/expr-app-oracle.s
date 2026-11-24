# SPDX-License-Identifier: Apache-2.0
# Identical driver for stock and interposed links. Assign constructed objects
# ordinal IDs so argument identity, ordering and sharing compare across ASLR.
.intel_syntax noprefix

.equ OWN_ROOT, 1
.equ HAS_BOUND, 2
.equ ARRAY_OUT, 4
.equ NAT_OUT, 8
.section .data.rel.ro
.balign 8
.Lops:
    .quad l_Lean_Expr_getAppFn, 0
    .quad l_Lean_Expr_getAppFn___boxed, OWN_ROOT
    .quad l_Lean_Expr_getAppFn_x27, 0
    .quad l_Lean_Expr_getAppFn_x27___boxed, OWN_ROOT
    .quad l_Lean_Expr_getAppNumArgs, NAT_OUT
    .quad l_Lean_Expr_getAppNumArgs___boxed, OWN_ROOT + NAT_OUT
    .quad l_Lean_Expr_getAppNumArgs_x27, NAT_OUT
    .quad l_Lean_Expr_getAppNumArgs_x27___boxed, OWN_ROOT + NAT_OUT
    .quad l_Lean_Expr_getBoundedAppFn, HAS_BOUND
    .quad l_Lean_Expr_getBoundedAppFn___boxed, HAS_BOUND + OWN_ROOT
    .quad l_Lean_Expr_getAppArgs, ARRAY_OUT + OWN_ROOT
    .quad l_Lean_Expr_getAppRevArgs, ARRAY_OUT + OWN_ROOT
    .quad l_Lean_Expr_getBoundedAppArgs, HAS_BOUND + ARRAY_OUT + OWN_ROOT
.Lops_end:
.section .rodata
.Lprefix: .asciz "%u/%u hb=%lu root=%d anchor=%d"
.Lhead:   .asciz " head=%u rc=%d"
.Lnat:    .asciz " nat=%lu"
.Larray:  .asciz " array=%lu/%lu rc=%d"
.Litem:   .asciz " %u"
.Lend:    .asciz " anchor_end=%d\n"
.Lboundary: .asciz "9223372036854775808"
.Lbig:      .asciz "1844674407370955161612345"

.bss
.balign 8
.Lnodes: .skip (1024*3 + 2)*8
.Lnode_count: .skip 8
.Lanchor: .skip 8
.Lroot: .skip 8
.Lresult: .skip 8
.Lbound: .skip 8
.Ldepth: .skip 4
.Lretain: .skip 4

.text
.globl main
.type main, @function
main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call lean_initialize_runtime_module@PLT
    mov edi, 1
    mov esi, 1
    call initialize_Lean_Expr@PLT
    cmp byte ptr [rax + 7], 0
    jne .Linit_error
    mov rdi, rax
    call .Ldrop
    call lean_io_mark_end_initialization@PLT
    xor r12d, r12d                      # seed, preserved through all helpers
.Lsample:
    lea r13, [rip + .Lops]
    xor r14d, r14d
.Lop:
    call .Lbuild
    mov r15, rax
    mov [rip + .Lroot], rax
    mov eax, r12d
    shr eax, 1
    and eax, 3
    cmp eax, 2
    jne .Lcheck_persistent
    mov rdi, r15
    call lean_mark_mt@PLT
    jmp .Lownership
.Lcheck_persistent:
    cmp r12d, 95
    jne .Lownership
    mov rdi, r15
    call lean_mark_persistent@PLT
.Lownership:
    mov dword ptr [rip + .Lretain], 1
    test byte ptr [r13 + 8], OWN_ROOT
    jz .Lbound_arg
    test r12d, 1
    jnz .Llast_owner
    mov rdi, r15
    call .Linc
    jmp .Lbound_arg
.Llast_owner:
    mov dword ptr [rip + .Lretain], 0
.Lbound_arg:
    test byte ptr [r13 + 8], HAS_BOUND
    jz .Lbegin
    call .Lmake_bound
    mov [rip + .Lbound], rax
.Lbegin:
    call _ZN4lean18get_num_heartbeatsEv@PLT
    mov rbx, rax
    mov rdi, r15
    test byte ptr [r13 + 8], HAS_BOUND
    jz .Lcall
    mov rdi, [rip + .Lbound]
    mov rsi, r15
.Lcall:
    call [r13]
    mov [rip + .Lresult], rax
    call _ZN4lean18get_num_heartbeatsEv@PLT
    sub rax, rbx
    mov rcx, rax
    mov r8d, 0x7fffffff                 # consumed root may already be freed
    cmp dword ptr [rip + .Lretain], 0
    je .Lprefix_row
    mov r8d, [r15]
.Lprefix_row:
    mov r9, [rip + .Lanchor]
    mov r9d, [r9]
    mov esi, r12d
    mov edx, r14d
    lea rdi, [rip + .Lprefix]
    xor eax, eax
    call printf@PLT

    mov r15, [rip + .Lresult]
    test byte ptr [r13 + 8], ARRAY_OUT
    jnz .Lshow_array
    test byte ptr [r13 + 8], NAT_OUT
    jnz .Lshow_nat
    mov rdi, r15
    call .Lid
    mov esi, eax
    mov edx, [r15]
    lea rdi, [rip + .Lhead]
    jmp .Lprint_value
.Lshow_nat:
    mov rsi, r15
    shr rsi, 1
    lea rdi, [rip + .Lnat]
.Lprint_value:
    xor eax, eax
    call printf@PLT
    jmp .Lrelease
.Lshow_array:
    mov rsi, [r15 + 8]
    mov rdx, [r15 + 16]
    mov ecx, [r15]
    lea rdi, [rip + .Larray]
    xor eax, eax
    call printf@PLT
    xor ebx, ebx
.Litems:
    cmp rbx, [r15 + 8]
    jae .Lrelease
    mov rdi, [r15 + 24 + rbx*8]
    call .Lid
    mov esi, eax
    lea rdi, [rip + .Litem]
    xor eax, eax
    call printf@PLT
    inc rbx
    jmp .Litems
.Lrelease:
    mov rdi, r15
    call .Ldrop
    cmp dword ptr [rip + .Lretain], 0
    je .Lrelease_anchor
    mov rdi, [rip + .Lroot]
    call .Ldrop
.Lrelease_anchor:
    mov rbx, [rip + .Lanchor]
    mov esi, [rbx]
    lea rdi, [rip + .Lend]
    xor eax, eax
    call printf@PLT
    mov rdi, rbx
    call .Ldrop
    add r13, 16
    inc r14d
    lea rax, [rip + .Lops_end]
    cmp r13, rax
    jb .Lop
    inc r12d
    cmp r12d, 97
    jb .Lsample
    xor eax, eax
    jmp .Lexit
.Linit_error:
    mov rdi, rax
    call lean_io_result_show_error@PLT
    mov eax, 1
.Lexit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size main, .-main

# Borrow the address book for identity checks; every node remains reachable from
# the input graph throughout construction. All pointers in the result must match.
.Lregister:
    mov rdx, [rip + .Lnode_count]
    lea rcx, [rip + .Lnodes]
    mov [rcx + rdx*8], rax
    inc qword ptr [rip + .Lnode_count]
    ret
.Lid:
    lea rcx, [rip + .Lnodes]
    xor eax, eax
.Lfind:
    cmp rax, [rip + .Lnode_count]
    jae .Lbad_pointer
    cmp rdi, [rcx + rax*8]
    je .Lfound
    inc eax
    jmp .Lfind
.Lbad_pointer:
    ud2
.Lfound:
    ret

.Lbuild:
    push rbx
    push r14
    push r15
    mov qword ptr [rip + .Lnode_count], 0
    lea edi, [r12*2 + 1]
    call lean_expr_mk_bvar@PLT
    call .Lregister
    mov [rip + .Lanchor], rax
    mov rbx, rax
    mov rdi, rbx
    call .Linc                          # independent observer for refcount checks
    mov r15d, r12d
    and r15d, 15
    cmp r12d, 96
    jne .Lhave_depth
    mov r15d, 1024
.Lhave_depth:
    mov [rip + .Ldepth], r15d
    xor r14d, r14d
.Lbuild_step:
    cmp r14d, r15d
    jae .Louter_metadata
    mov eax, r14d
    and eax, 3
    cmp eax, 1
    je .Lrepeat_anchor
    cmp eax, 3
    je .Lsame_subtree
    lea edi, [r14*2 + 7]
    call lean_expr_mk_bvar@PLT
    call .Lregister
    mov rsi, rax
    jmp .Lapp
.Lrepeat_anchor:
    mov rdi, [rip + .Lanchor]
    jmp .Lshared_arg
.Lsame_subtree:
    mov rdi, rbx
.Lshared_arg:
    mov rsi, rdi                        # these ST objects are local while building
    inc dword ptr [rdi]
.Lapp:
    mov rdi, rbx
    call lean_expr_mk_app@PLT
    call .Lregister
    mov rbx, rax
    cmp r12d, 96
    je .Lnext
    test r12d, 4
    jz .Lnext
    mov eax, r14d
    and eax, 3
    cmp eax, 2
    jne .Lnext
    mov edi, 1
    mov rsi, rbx
    call lean_expr_mk_mdata@PLT
    call .Lregister
    mov rbx, rax
.Lnext:
    inc r14d
    jmp .Lbuild_step
.Louter_metadata:
    test r12d, 16
    jz .Lbuilt
    mov edi, 1
    mov rsi, rbx
    call lean_expr_mk_mdata@PLT
    call .Lregister
    mov rbx, rax
.Lbuilt:
    mov rax, rbx
    pop r15
    pop r14
    pop rbx
    ret

.Lmake_bound:
    mov eax, r12d
    shr eax, 1
    and eax, 7
    cmp eax, 3
    jb .Ltag_bound                       # 0, 1, 2
    cmp eax, 4
    ja .Lwide
    sub eax, 3
    add eax, [rip + .Ldepth]             # depth, depth+1
.Ltag_bound:
    lea rax, [rax*2 + 1]
    ret
.Lwide:
    cmp eax, 5
    jne .Lheap_nat
    mov rax, -1
    ret
.Lheap_nat:
    lea rdi, [rip + .Lboundary]
    cmp eax, 6
    je lean_cstr_to_nat@PLT
    lea rdi, [rip + .Lbig]
    jmp lean_cstr_to_nat@PLT

.Linc:
    cmp dword ptr [rdi], 0
    je .Lreturned
    jl lean_inc_ref_cold@PLT
    inc dword ptr [rdi]
    ret
.Ldrop:
    test dil, 1
    jnz .Lreturned
    cmp dword ptr [rdi], 1
    jg .Ldecrement
    cmp dword ptr [rdi], 0
    jne lean_dec_ref_cold@PLT
.Lreturned:
    ret
.Ldecrement:
    dec dword ptr [rdi]
    ret

.section .note.GNU-stack,"",@progbits
