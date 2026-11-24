# SPDX-License-Identifier: Apache-2.0
# Differential driver for the public v4.19.0 Expr lifting/lowering C ABI.
# Label all input objects by encounter order before calling either operation.
# The result uses the same labels, so equality of records checks both sharing
# within the output and identity with the caller's still-live input graph.
.intel_syntax noprefix

.section .rodata
.Lname: .asciz "shift_fixture"
.Lwide: .asciz "9223372036854775808"
.Lwider: .asciz "184467440737095516161234567"
.Lcase: .asciz "%d/%d/%d/%d hb=%lu"
.Lnode: .asciz " (%u:t%u,r%d,d%016lx,f%u"
.Lref: .asciz " @%u"
.Lscalar: .asciz " #%lu"
.Lpayload: .asciz " &%u"
# Bit i identifies a child expression in constructor object slot i.
.Lchild_masks: .byte 0,0,0,0,0,3,6,6,14,0,2,4
.balign 8
.Lparams:
.macro param s, d
    .quad 2*(\s)+1, 2*(\d)+1
.endm
    param 0, 0
    param 0, 1
    param 1, 0
    param 1, 1
    param 1, 2
    param 2, 1
    param 3, 2
    param 4, 4
    param 7, 3
    param 12, 2
    param 700, 3
    param 1048555, 1
    param 4294967295, 1
    param 4294967296, 1
    param 4294967297, 4
    param 4294967298, 4294967297
    .quad -1, -1                       # maximum immediate Nat, both operands
    .quad 0, 3                         # 0 and 2 here stand for the two heap Nats
    .quad 5, 2
    .quad 2, 0
.equ NPARAM, (. - .Lparams) / 16
.equ NFIXTURE, 18
.equ CAPACITY, 2048

.bss
.balign 8
.Lwide_args: .skip 16
.Lobjects: .skip CAPACITY * 8
.Lseen: .skip CAPACITY * 4
.Lbaseline: .skip CAPACITY * 4
.Lcount: .skip 4
.Loriginal_count: .skip 4
.Lgeneration: .skip 4
.Lemit: .skip 4
.Lroot: .skip 8
.Lresult: .skip 8
.Lheartbeat: .skip 8

.text
.globl main
.type main,@function
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
    jne .Lbad_init
    mov rdi, rax
    call .Ldrop
    call lean_io_mark_end_initialization@PLT
    lea rdi, [rip + .Lwide]
    call lean_cstr_to_nat@PLT
    mov [rip + .Lwide_args], rax
    lea rdi, [rip + .Lwider]
    call lean_cstr_to_nat@PLT
    mov [rip + .Lwide_args + 8], rax

    xor r12d, r12d                      # fixture index
.Lfixture:
    xor r13d, r13d                      # single-threaded / MT / persistent
.Lmode:
    call .Lbuild
    mov [rip + .Lroot], rax
    mov rdi, rax
    cmp r13d, 1
    jne .Lmaybe_persistent
    call lean_mark_mt@PLT
    jmp .Lnumber_input
.Lmaybe_persistent:
    cmp r13d, 2
    jne .Lnumber_input
    call lean_mark_persistent@PLT
.Lnumber_input:
    mov dword ptr [rip + .Lemit], 0
    mov dword ptr [rip + .Lcount], 0
    inc dword ptr [rip + .Lgeneration]
    mov rdi, [rip + .Lroot]
    call .Lvisit
    mov ecx, [rip + .Lcount]
    mov [rip + .Loriginal_count], ecx
    lea rdi, [rip + .Lobjects]
    lea rsi, [rip + .Lbaseline]
.Lsnapshot:
    mov rax, [rdi + rcx*8 - 8]
    mov eax, [rax]
    mov [rsi + rcx*4 - 4], eax
    dec ecx
    jnz .Lsnapshot

    mov dword ptr [rip + .Lemit], 1
    xor r14d, r14d                      # borrowed lift/lower, consuming lift/lower
.Loperation:
    xor r15d, r15d
.Ltrial:
    call _ZN4lean18get_num_heartbeatsEv@PLT
    mov [rip + .Lheartbeat], rax
    lea rax, [rip + .Lparams]
    mov edx, r15d
    shl edx, 4
    add rax, rdx
    mov rsi, [rax]
    mov rdx, [rax + 8]
    lea rax, [rip + .Lwide_args]
    test sil, 1
    jnz .Ldelta
    mov rsi, [rax + rsi*4]
.Ldelta:
    test dl, 1
    jnz .Linvoke
    mov rdx, [rax + rdx*4]
.Linvoke:
    mov rdi, [rip + .Lroot]
    cmp r14d, 2
    jae .Lboxed
    test r14d, r14d
    jnz .Llower
    call lean_expr_lift_loose_bvars@PLT
    jmp .Lserialize
.Llower:
    call lean_expr_lower_loose_bvars@PLT
    jmp .Lserialize
.Lboxed:
    sub rsp, 16
    mov [rsp], rsi
    mov [rsp + 8], rdx
    call .Lown                         # observer still owns the input graph
    mov rdi, [rsp]
    call .Lown
    mov rdi, [rsp + 8]
    call .Lown
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    add rsp, 16
    mov rdi, [rip + .Lroot]
    cmp r14d, 2
    jne .Lboxed_lower
    call l_Lean_Expr_liftLooseBVars___boxed@PLT
    jmp .Lserialize
.Lboxed_lower:
    call l_Lean_Expr_lowerLooseBVars___boxed@PLT
.Lserialize:
    mov [rip + .Lresult], rax
    call _ZN4lean18get_num_heartbeatsEv@PLT
    sub rax, [rip + .Lheartbeat]
    lea rdi, [rip + .Lcase]
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r15d
    mov r9, rax
    xor eax, eax
    call printf@PLT
    inc dword ptr [rip + .Lgeneration]
    mov eax, [rip + .Loriginal_count]
    mov [rip + .Lcount], eax
    mov rdi, [rip + .Lresult]
    call .Lvisit
    mov edi, 10
    call putchar@PLT
    mov rdi, [rip + .Lresult]
    call .Ldrop

    # Releasing the result must restore every original object's raw count.
    lea rdi, [rip + .Lobjects]
    lea rsi, [rip + .Lbaseline]
    mov ecx, [rip + .Loriginal_count]
.Lcheck_rc:
    mov rax, [rdi + rcx*8 - 8]
    mov eax, [rax]
    cmp eax, [rsi + rcx*4 - 4]
    jne .Lbad_rc
    dec ecx
    jnz .Lcheck_rc
    mov rax, [rip + .Lwide_args]
    cmp dword ptr [rax], 1
    jne .Lbad_rc
    mov rax, [rip + .Lwide_args + 8]
    cmp dword ptr [rax], 1
    jne .Lbad_rc
    inc r15d
    cmp r15d, NPARAM
    jb .Ltrial
    inc r14d
    cmp r14d, 4
    jb .Loperation
    mov rdi, [rip + .Lroot]
    call .Ldrop
    inc r13d
    cmp r13d, 3
    jb .Lmode
    inc r12d
    cmp r12d, NFIXTURE
    jb .Lfixture

    # A boxed call also consumes an exclusively owned changed root. Retain
    # its original child to observe destruction of the old parent's only edge.
    xor r12d, r12d
.Lexclusive:
    mov edi, 9                          # #4
    call lean_expr_mk_bvar@PLT
    mov rbx, rax
    inc dword ptr [rbx]
    mov rsi, rbx
    mov edi, 1
    call lean_expr_mk_mdata@PLT
    mov rdi, rax
    mov esi, 9                          # cutoff 4
    mov edx, 3                          # delta 1
    test r12d, r12d
    jnz .Lexclusive_lower
    call l_Lean_Expr_liftLooseBVars___boxed@PLT
    mov esi, 11                         # #5
    jmp .Lcheck_exclusive
.Lexclusive_lower:
    call l_Lean_Expr_lowerLooseBVars___boxed@PLT
    mov esi, 7                          # #3
.Lcheck_exclusive:
    cmp dword ptr [rbx], 1
    jne .Lbad_rc
    cmp byte ptr [rax + 7], 10
    jne .Lbad_rc
    mov rdx, [rax + 16]
    cmp byte ptr [rdx + 7], 0
    jne .Lbad_rc
    cmp [rdx + 8], rsi
    jne .Lbad_rc
    mov rdi, rax
    call .Ldrop
    mov rdi, rbx
    call .Ldrop
    inc r12d
    cmp r12d, 2
    jb .Lexclusive

    mov rdi, [rip + .Lwide_args]
    call .Ldrop
    mov rdi, [rip + .Lwide_args + 8]
    call .Ldrop
    xor eax, eax
    jmp .Lexit
.Lbad_init:
    mov rdi, rax
    call lean_io_result_show_error@PLT
    mov eax, 1
    jmp .Lexit
.Lbad_rc:
    mov eax, 2
.Lexit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size main, . - main

# Fixture constructors consume an owned reference for each object parameter.
# During construction these nodes are single-threaded and carry positive RC.
.Lbuild:
    push rbx
    push r14
    push r15
    sub rsp, 16
    cmp r12d, 0
    je .Lbvar_zero
    cmp r12d, 1
    je .Lbvar_twelve
    cmp r12d, 2
    je .Lclosed_binder
    cmp r12d, 3
    je .Lclosed_leaves
    cmp r12d, 16
    je .Ldeep
    cmp r12d, 17
    je .Lnear_limit

    mov eax, r12d
    and eax, 3
    lea edi, [rax*2 + 1]
    call lean_expr_mk_bvar@PLT
    mov rbx, rax
    mov eax, r12d
    and eax, 7
    lea edi, [rax*2 + 5]
    call lean_expr_mk_bvar@PLT
    mov rdi, rbx
    mov rsi, rax
    call lean_expr_mk_app@PLT
    mov rbx, rax                        # shared at equal and different depths
    lea rdi, [rip + .Lname]
    call lean_mk_string@PLT
    mov rdi, rax
    call l_Lean_Name_mkStr1@PLT
    mov r14, rax                        # binder and projection name
    add dword ptr [rbx], 4              # lambda twice, let twice, forall once
    add dword ptr [r14], 4              # lambda, let, forall, KV key, projection
    mov rdi, r14
    mov rsi, rbx
    mov rdx, rbx
    mov ecx, r12d
    and ecx, 3
    call lean_expr_mk_lambda@PLT
    mov rdi, r14
    mov rsi, rbx
    mov rdx, rax
    mov rcx, rbx
    mov r8d, r12d
    and r8d, 1                          # exercise both nonDep flags
    call l_Lean_mkLet@PLT
    mov rdi, r14
    mov rsi, rbx
    mov rdx, rax
    lea ecx, [r12 + 1]
    and ecx, 3
    call lean_expr_mk_forall@PLT
    inc dword ptr [rax]
    mov rdi, rax
    mov rsi, rax
    call lean_expr_mk_app@PLT
    mov r15, rax
    mov edi, 1                          # empty KVMap
    mov rsi, r14
    mov edx, 1
    call l_Lean_KVMap_setBool@PLT
    mov rdi, rax
    mov rsi, r15
    call lean_expr_mk_mdata@PLT
    mov rdi, r14
    lea esi, [r12*2 + 1]
    mov rdx, rax
    call lean_expr_mk_proj@PLT
    mov r15, rax
    call .Lleaves
    mov rdi, r15
    mov rsi, rax
    call lean_expr_mk_app@PLT
    jmp .Lbuilt
.Lbvar_zero:
    mov edi, 1
    jmp .Lbvar
.Lbvar_twelve:
    mov edi, 25
    jmp .Lbvar
.Lnear_limit:
    mov edi, 2*1048555 + 1
.Lbvar:
    call lean_expr_mk_bvar@PLT
    jmp .Lbuilt
.Lclosed_binder:
    mov edi, 1
    call lean_expr_mk_bvar@PLT
    mov rbx, rax
    mov edi, 1
    call lean_level_mk_zero@PLT
    mov rdi, rax
    call lean_expr_mk_sort@PLT
    mov edi, 1
    mov rsi, rax
    mov rdx, rbx
    xor ecx, ecx
    call lean_expr_mk_forall@PLT
    jmp .Lbuilt
.Lclosed_leaves:
    call .Lleaves
    jmp .Lbuilt
.Ldeep:
    mov edi, 2*720 + 1
    call lean_expr_mk_bvar@PLT
    mov r15, rax
    mov edi, 1
    mov esi, 1
    call lean_expr_mk_const@PLT
    mov rbx, rax
    mov r14d, 256
    add dword ptr [rbx], 255
.Ldeeper:
    mov edi, 1
    mov rsi, rbx
    mov rdx, r15
    mov ecx, 1
    call lean_expr_mk_lambda@PLT
    mov r15, rax
    dec r14d
    jnz .Ldeeper
.Lbuilt:
    add rsp, 16
    pop r15
    pop r14
    pop rbx
    ret

.Lleaves:
    push rbx
    mov edi, 1
    call lean_level_mk_zero@PLT
    mov rdi, rax
    call lean_expr_mk_sort@PLT
    mov rbx, rax
.macro add_leaf ctor
    call \ctor@PLT
    mov rsi, rax
    mov rdi, rbx
    call lean_expr_mk_app@PLT
    mov rbx, rax
.endm
    mov edi, 1
    add_leaf lean_expr_mk_fvar
    mov edi, 1
    add_leaf lean_expr_mk_mvar
    mov edi, 1
    mov esi, 1
    add_leaf lean_expr_mk_const
    mov edi, 151
    add_leaf l_Lean_mkNatLit
    pop rbx
    ret

# rdi = heap pointer. Labels form a single namespace for Exprs and payloads.
.Lid:
    lea rdx, [rip + .Lobjects]
    mov ecx, [rip + .Lcount]
    xor eax, eax
.Lsearch:
    cmp eax, ecx
    je .Ladd
    cmp [rdx + rax*8], rdi
    je .Lfound
    inc eax
    jmp .Lsearch
.Ladd:
    cmp eax, CAPACITY
    jae .Lcapacity_error
    mov [rdx + rax*8], rdi
    inc dword ptr [rip + .Lcount]
.Lfound:
    ret
.Lcapacity_error:
    ud2

# First visit emits a full definition. Repeated visits emit a reference.
.Lvisit:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    call .Lid
    mov r13d, eax
    lea rcx, [rip + .Lseen]
    mov edx, [rip + .Lgeneration]
    cmp [rcx + rax*4], edx
    je .Lrepeat
    mov [rcx + rax*4], edx
    movzx ebx, byte ptr [r12 + 7]
    movzx r14d, byte ptr [r12 + 6]
    cmp dword ptr [rip + .Lemit], 0
    je .Lfields
    mov r8, [r12 + r14*8 + 8]         # computed-field data follows all object fields
    xor r9d, r9d
    cmp ebx, 6
    jb .Lnode_header
    cmp ebx, 8
    ja .Lnode_header
    movzx r9d, byte ptr [r12 + r14*8 + 16]
.Lnode_header:
    lea rdi, [rip + .Lnode]
    mov esi, r13d
    mov edx, ebx
    mov ecx, [r12]
    xor eax, eax
    call printf@PLT
.Lfields:
    lea rax, [rip + .Lchild_masks]
    movzx ebx, byte ptr [rax + rbx]
    xor r15d, r15d
.Lfield:
    cmp r15d, r14d
    jae .Lclose
    mov rdi, [r12 + r15*8 + 8]
    bt ebx, r15d
    jc .Lchild
    test dil, 1
    jnz .Ltagged
    call .Lid
    mov esi, eax
    lea rdi, [rip + .Lpayload]
    jmp .Lfield_print
.Ltagged:
    mov rsi, rdi
    shr rsi, 1
    lea rdi, [rip + .Lscalar]
.Lfield_print:
    cmp dword ptr [rip + .Lemit], 0
    je .Lnext
    xor eax, eax
    call printf@PLT
    jmp .Lnext
.Lchild:
    call .Lvisit
.Lnext:
    inc r15d
    jmp .Lfield
.Lclose:
    cmp dword ptr [rip + .Lemit], 0
    je .Lvisited
    mov edi, ')'
    call putchar@PLT
    jmp .Lvisited
.Lrepeat:
    cmp dword ptr [rip + .Lemit], 0
    je .Lvisited
    mov esi, r13d
    lea rdi, [rip + .Lref]
    xor eax, eax
    call printf@PLT
.Lvisited:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.Lown:
    test dil, 1
    jnz .Lowned
    cmp dword ptr [rdi], 0
    je .Lowned
    jl lean_inc_ref_cold@PLT
    inc dword ptr [rdi]
.Lowned:
    ret

.Ldrop:
    test dil, 1
    jnz .Ldropped
    mov eax, [rdi]
    cmp eax, 1
    jg .Llocal
    test eax, eax
    jne lean_dec_ref_cold@PLT
.Ldropped:
    ret
.Llocal:
    dec dword ptr [rdi]
    ret

.section .note.GNU-stack,"",@progbits
