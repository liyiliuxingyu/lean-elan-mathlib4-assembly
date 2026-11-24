# SPDX-License-Identifier: Apache-2.0
# Link this same driver once to Lean 4.19.0 alone and once with kernel-data.o.
# Constructors, memory management and initialization come from the official DSO.
.intel_syntax noprefix
.equ N_LEVELS, 6
.equ N_EXPRS, 12
.equ NAME_SLOT, N_LEVELS + N_EXPRS
.section .rodata
.Lrow: .asciz "%u %lu %lu %d\n"            # ordinal, value, heartbeats, refcount
.Lstring: .asciz "Lean \316\273"
.section .data.rel.ro
.p2align 3
.Llevel_ops:
    .quad lean_level_hash, 0xffffffff
    .quad lean_level_has_mvar, 255
    .quad lean_level_has_param, 255
    .quad lean_level_depth, 0xffffffff
.Llevel_end:
.Lexpr_ops:
    .quad lean_expr_hash, -1
    .quad lean_expr_has_fvar, 255
    .quad lean_expr_has_expr_mvar, 255
    .quad lean_expr_has_level_mvar, 255
    .quad lean_expr_has_mvar, 255
    .quad lean_expr_has_level_param, 255
    .quad lean_expr_loose_bvar_range, 0xffffffff
    .quad lean_expr_binder_info, 255
.Lexpr_end:
.bss
.balign 8
.Lslots:  .skip (NAME_SLOT+1)*8
.Lordinal: .skip 4
.text

# All inputs used during construction are single-threaded, persistent or scalar.
# Take an additional owned reference for the constructor.
.macro own source, dest
    mov \dest, [rbx + (\source)*8]
    test \dest, 1
    jnz .Lown_done_\@
    cmp dword ptr [\dest], 0
    je .Lown_done_\@
    inc dword ptr [\dest]
.Lown_done_\@:
.endm
.macro save slot, constructor
    call \constructor@PLT
    mov [rbx + (\slot)*8], rax
.endm
.macro bindinfo
    mov ecx, r12d
    and ecx, 3
.endm

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
    jne .Lerror
    mov rdi, rax
    call .Ldrop
    call lean_io_mark_end_initialization@PLT
    lea rbx, [rip + .Lslots]
    xor r12d, r12d
.Lsample:
    mov edi, 1                              # Name.num Name.anonymous seed
    lea rsi, [r12*2 + 1]
    save NAME_SLOT, lean_name_mk_numeral
    mov edi, 1
    save 0, lean_level_mk_zero
    own 0, rdi
    save 1, lean_level_mk_succ
    own NAME_SLOT, rdi
    save 2, lean_level_mk_param
    own NAME_SLOT, rdi
    save 3, lean_level_mk_mvar
    own 1, rdi
    own 2, rsi
    save 4, lean_level_mk_max
    own 4, rdi
    own 3, rsi
    save 5, lean_level_mk_imax

    imul edi, r12d, 104729
    and edi, 0xfffff
    cmp r12d, 127
    jne .Lbvar_ready
    mov edi, 0xffffe                        # largest representable loose index
.Lbvar_ready:
    lea rdi, [rdi*2 + 1]
    save 6, lean_expr_mk_bvar
    own NAME_SLOT, rdi
    save 7, lean_expr_mk_fvar
    own NAME_SLOT, rdi
    save 8, lean_expr_mk_mvar
    mov eax, r12d
    xor edx, edx
    mov ecx, N_LEVELS
    div ecx
    own rdx, rdi
    save 9, lean_expr_mk_sort
    own NAME_SLOT, rdi
    mov esi, 1                              # List.nil
    save 10, lean_expr_mk_const
    own 7, rdi
    own 6, rsi
    save 11, lean_expr_mk_app
    own NAME_SLOT, rdi
    own 9, rsi
    own 11, rdx
    bindinfo
    save 12, lean_expr_mk_lambda
    own NAME_SLOT, rdi
    own 12, rsi
    own 8, rdx
    bindinfo
    save 13, lean_expr_mk_forall
    own NAME_SLOT, rdi
    own 9, rsi
    own 8, rdx
    own 13, rcx
    save 14, lean_expr_mk_let
    test r12d, 1
    jnz .Lstring_lit
    lea rdi, [r12*2 + 1]
    save 15, l_Lean_mkRawNatLit
    jmp .Lmetadata
.Lstring_lit:
    lea rdi, [rip + .Lstring]
    call lean_mk_string@PLT
    mov rdi, rax
    save 15, l_Lean_mkStrLit
.Lmetadata:
    mov edi, 1                              # KVMap.empty = List.nil
    own 14, rsi
    save 16, lean_expr_mk_mdata
    own NAME_SLOT, rdi
    lea rsi, [r12*2 + 1]
    own 16, rdx
    save 17, lean_expr_mk_proj

    # Alternate local/atomic refcounts. One sample exercises persistent values.
    test r12d, 1
    jz .Lqueries
    xor r13d, r13d
.Lmark:
    mov rdi, [rbx + r13*8]
    test dil, 1
    jnz .Lmarked
    cmp r12d, 127
    je .Lmark_persistent
    call lean_mark_mt@PLT
    jmp .Lmarked
.Lmark_persistent:
    call lean_mark_persistent@PLT
.Lmarked:
    inc r13d
    cmp r13d, NAME_SLOT + 1
    jb .Lmark

.Lqueries:
    mov rdi, [rbx + NAME_SLOT*8]
    call .Ldrop
    mov r13d, NAME_SLOT
.Lnext_object:
    dec r13d
    mov rdi, [rbx + r13*8]
    lea rsi, [rip + .Lexpr_ops]
    lea rdx, [rip + .Lexpr_end]
    cmp r13d, N_LEVELS
    jae .Lrun
    lea rsi, [rip + .Llevel_ops]
    lea rdx, [rip + .Llevel_end]
.Lrun:
    call .Lobserve
    test r13d, r13d
    jnz .Lnext_object
    inc r12d
    cmp r12d, 128
    jb .Lsample
    xor eax, eax
    jmp .Ldone
.Lerror:
    mov rdi, rax
    call lean_io_result_show_error@PLT
    mov eax, 1
.Ldone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size main, . - main

# Consume an object by running its family of accessors. The last accessor takes
# the driver's owned reference, so exclusive objects reach the real deallocator.
.Lobserve:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
.Lnext_op:
    lea rax, [r13 + 16]
    cmp rax, r14
    je .Lobserve_call
    mov rdi, r12
    test dil, 1
    jnz .Lobserve_call
    cmp dword ptr [rdi], 0
    je .Lobserve_call
    jl .Linc_atomic
    inc dword ptr [rdi]
    jmp .Lobserve_call
.Linc_atomic:
    call lean_inc_ref_cold@PLT
.Lobserve_call:
    call _ZN4lean18get_num_heartbeatsEv@PLT
    mov r15, rax
    mov rdi, r12
    call [r13]
    and rax, [r13 + 8]                    # observe only bits specified by the ABI
    mov rbx, rax
    call _ZN4lean18get_num_heartbeatsEv@PLT
    sub rax, r15
    mov rcx, rax
    xor r8d, r8d
    add r13, 16
    cmp r13, r14
    je .Lprint                            # last call may have freed the object
    test r12b, 1
    jnz .Lprint
    mov r8d, [r12]
.Lprint:
    mov esi, [rip + .Lordinal]
    inc dword ptr [rip + .Lordinal]
    lea rdi, [rip + .Lrow]
    mov rdx, rbx
    xor eax, eax
    call printf@PLT
    cmp r13, r14
    jb .Lnext_op
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.Ldrop:
    test dil, 1
    jnz .Ldrop_done
    cmp dword ptr [rdi], 1
    jg .Ldec
    cmp dword ptr [rdi], 0
    jne lean_dec_ref_cold@PLT
.Ldrop_done:
    ret
.Ldec:
    dec dword ptr [rdi]
    ret
.section .note.GNU-stack,"",@progbits
