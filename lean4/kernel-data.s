# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2018 Microsoft Corporation. Original author: Leonardo de Moura.
# Native exports from Lean/Expr.lean and Lean/Level.lean, v4.19.0.
.intel_syntax noprefix
.text

# Expr stores its computed UInt64 immediately after its object-pointer fields.
# Nonzero Level constructors use the same layout. Level.zero is lean_box(0).
.macro cached_word
    movzx ecx, byte ptr [rdi + 6]          # lean_ctor_num_objs
    mov rax, [rdi + rcx*8 + 8]
.endm

.macro project shift, width
.if \shift
    shr rax, \shift
.endif
.if \width == 1
    and eax, 1
.elseif \width == 2
    and eax, 3                            # either metavariable flag
    setne al
.elseif \width == 32
    mov eax, eax                          # UInt32 hash, including Expr.hash
.endif
.endm

.macro expr_export name, shift, width
.globl lean_expr_\name
.type lean_expr_\name, @function
lean_expr_\name:
    .cfi_startproc
    cached_word
    project \shift, \width
    jmp .Lconsume
    .cfi_endproc
.size lean_expr_\name, . - lean_expr_\name
.endm

expr_export hash,             0, 32
expr_export has_fvar,        40,  1
expr_export has_expr_mvar,   41,  1
expr_export has_level_mvar,  42,  1
expr_export has_mvar,        41,  2
expr_export has_level_param, 43,  1
expr_export loose_bvar_range,44, 20

.globl lean_expr_binder_info
.type lean_expr_binder_info, @function
lean_expr_binder_info:
    .cfi_startproc
    xor eax, eax                          # .default
    movzx ecx, byte ptr [rdi + 7]
    and ecx, -2                           # .lam (6) or .forallE (7)
    cmp ecx, 6
    jne .Lconsume
    movzx eax, byte ptr [rdi + 40]        # name, domain, body, data, BinderInfo
    jmp .Lconsume
    .cfi_endproc
.size lean_expr_binder_info, . - lean_expr_binder_info

.macro level_export name, shift, width, zero
.globl lean_level_\name
.type lean_level_\name, @function
lean_level_\name:
    .cfi_startproc
    test dil, 1
    jnz .Lzero_\@
    cached_word
    project \shift, \width
    jmp .Llevel_heartbeat
.Lzero_\@:
    mov eax, \zero
    ret
    .cfi_endproc
.size lean_level_\name, . - lean_level_\name
.endm

level_export hash,       0, 32, 2221
level_export has_mvar,  32,  1,    0
level_export has_param, 33,  1,    0
level_export depth,     40, 24,    0

# In the official Linux build, reading a nonzero Level boxes the cached UInt64
# temporarily. Charge that allocation's heartbeat while using the word directly.
.Llevel_heartbeat:
    .cfi_startproc
    sub rsp, 24
    .cfi_adjust_cfa_offset 24
    mov [rsp], rdi
    mov [rsp + 8], rax
    call lean_inc_heartbeat@PLT
    mov rdi, [rsp]
    mov rax, [rsp + 8]
    add rsp, 24
    .cfi_adjust_cfa_offset -24
    .cfi_endproc

# Each named export consumes one owned reference. rdi is a non-scalar here.
# lean.h routes the last single-thread reference and all multi-threaded objects
# to the official runtime, which handles child releases and atomic refcounts.
.Lconsume:
    .cfi_startproc
    mov ecx, [rdi]
    cmp ecx, 1
    jg .Lshared
    test ecx, ecx
    jz .Lpersistent
    push rax
    .cfi_adjust_cfa_offset 8
    call lean_dec_ref_cold@PLT
    pop rax
    .cfi_adjust_cfa_offset -8
.Lpersistent:
    ret
.Lshared:
    sub dword ptr [rdi], 1
    ret
    .cfi_endproc

.section .note.GNU-stack,"",@progbits
