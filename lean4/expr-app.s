# SPDX-License-Identifier: Apache-2.0
# Application-spine operations from Lean/Expr.lean, v4.19.0, Linux x86-64.
.intel_syntax noprefix
.text

# Non-scalar Expr values carry the constructor tag at offset 7. An application
# (5) stores its function at +8 and argument at +16. Metadata (10) wraps the
# expression at +16. Only the primed functions pass through metadata.
.macro spine_query name, count, skip_metadata
.globl l_Lean_Expr_\name
.type l_Lean_Expr_\name, @function
l_Lean_Expr_\name:
    .cfi_startproc
.if \count
    mov eax, 1                          # lean_box(0)
.endif
.Ltag_\@:
    movzx ecx, byte ptr [rdi + 7]
    cmp ecx, 5
    je .Lapp_\@
.if \skip_metadata
    cmp ecx, 10
    jne .Ldone_\@
    mov rdi, [rdi + 16]
    jmp .Ltag_\@
.else
    jmp .Ldone_\@
.endif
.Lapp_\@:
    mov rdi, [rdi + 8]
.if \count
    add rax, 2                          # one more distinct application node
.endif
    jmp .Ltag_\@
.Ldone_\@:
.if \count
    ret
.else
    jmp .Lowned_expr
.endif
    .cfi_endproc
.size l_Lean_Expr_\name, . - l_Lean_Expr_\name
.endm

spine_query getAppFn,          0, 0
spine_query getAppFn_x27,      0, 1
spine_query getAppNumArgs,     1, 0
spine_query getAppNumArgs_x27, 1, 1

# Convert a borrowed non-scalar Expr pointer in rdi into an owned result.
.Lowned_expr:
    .cfi_startproc
    mov rax, rdi
    cmp dword ptr [rdi], 0
    je .Lkeep_done                       # persistent or compacted
    jl .Lkeep_atomic
    inc dword ptr [rdi]
.Lkeep_done:
    ret
.Lkeep_atomic:
    push rdi
    .cfi_adjust_cfa_offset 8
    call lean_inc_ref_cold@PLT
    pop rax
    .cfi_adjust_cfa_offset -8
    ret
    .cfi_endproc

# The public wrappers used as Lean closures consume the caller's Expr.
.macro boxed name, exprreg
.globl l_Lean_Expr_\name\()___boxed
.type l_Lean_Expr_\name\()___boxed, @function
l_Lean_Expr_\name\()___boxed:
    .cfi_startproc
    push \exprreg
    .cfi_adjust_cfa_offset 8
    call l_Lean_Expr_\name
    mov rdi, [rsp]
    mov [rsp], rax
    call .Ldrop
    pop rax
    .cfi_adjust_cfa_offset -8
    ret
    .cfi_endproc
.size l_Lean_Expr_\name\()___boxed, . - l_Lean_Expr_\name\()___boxed
.endm

boxed getAppFn, rdi
boxed getAppFn_x27, rdi
boxed getAppNumArgs, rdi
boxed getAppNumArgs_x27, rdi

# Consume one heap reference. Cold decrements include last-owner destruction
# and Lean's atomic multi-threaded path. Scalar arguments are handled by callers.
.Ldrop:
    .cfi_startproc
    mov ecx, [rdi]
    cmp ecx, 1
    jg .Ldrop_local
    test ecx, ecx
    jne lean_dec_ref_cold@PLT
    ret
.Ldrop_local:
    dec dword ptr [rdi]
    ret
    .cfi_endproc

.globl l_Lean_Expr_getBoundedAppFn
.type l_Lean_Expr_getBoundedAppFn, @function
l_Lean_Expr_getBoundedAppFn:
    .cfi_startproc
    # maxArgs (owned Nat), e (borrowed Expr)
    test dil, 1
    jz .Llarge_bound
.Lsmall_bound:
    cmp rdi, 1
    je .Lbounded_head
    cmp byte ptr [rsi + 7], 5
    jne .Lbounded_head
    sub rdi, 2
    mov rsi, [rsi + 8]
    jmp .Lsmall_bound
.Lbounded_head:
    mov rdi, rsi
    jmp .Lowned_expr

.Llarge_bound:
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_offset r12, -16
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_offset r13, -24
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_offset rbx, -32
    mov r12, rdi
    mov r13, rsi
.Lbig_step:
    cmp byte ptr [r13 + 7], 5
    jne .Lbig_done
    mov r13, [r13 + 8]
    mov rdi, r12
    mov esi, 3                          # lean_box(1)
    call lean_nat_big_sub@PLT
    mov rbx, rax
    mov rdi, r12
    call .Ldrop
    mov r12, rbx
    test r12b, 1                        # may have become a small Nat
    jz .Lbig_step
    jmp .Lresume_small
.Lbig_done:
    mov rdi, r12
    call .Ldrop
    mov r12d, 1                         # stop at this node
.Lresume_small:
    mov rdi, r12
    mov rsi, r13
    pop rbx
    .cfi_restore rbx
    .cfi_adjust_cfa_offset -8
    pop r13
    .cfi_restore r13
    .cfi_adjust_cfa_offset -8
    pop r12
    .cfi_restore r12
    .cfi_adjust_cfa_offset -8
    jmp .Lsmall_bound
    .cfi_endproc
.size l_Lean_Expr_getBoundedAppFn, . - l_Lean_Expr_getBoundedAppFn
boxed getBoundedAppFn, rsi

# Array-producing interfaces consume the spine. Their result is a fresh exact-
# capacity Array Expr, including on empty input. Hold the input root until all
# argument references have transferred to array slots. This also works when a
# function and argument share a subtree or an argument occurs more than once.
.globl l_Lean_Expr_getAppArgs
.type l_Lean_Expr_getAppArgs, @function
l_Lean_Expr_getAppArgs:
    mov rsi, rdi
    mov rdi, -1                         # largest immediate Nat
    xor edx, edx                        # natural order
    jmp .Lcollect
.size l_Lean_Expr_getAppArgs, . - l_Lean_Expr_getAppArgs

.globl l_Lean_Expr_getAppRevArgs
.type l_Lean_Expr_getAppRevArgs, @function
l_Lean_Expr_getAppRevArgs:
    mov rsi, rdi
    mov rdi, -1
    mov edx, 1                          # outermost application first
    jmp .Lcollect
.size l_Lean_Expr_getAppRevArgs, . - l_Lean_Expr_getAppRevArgs

.globl l_Lean_Expr_getBoundedAppArgs
.type l_Lean_Expr_getBoundedAppArgs, @function
l_Lean_Expr_getBoundedAppArgs:
    xor edx, edx                        # maxArgs and expression both owned
    jmp .Lcollect
.size l_Lean_Expr_getBoundedAppArgs, . - l_Lean_Expr_getBoundedAppArgs

.Lcollect:
    .cfi_startproc
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_offset rbx, -16
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_offset r12, -24
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_offset r13, -32
    push r14
    .cfi_adjust_cfa_offset 8
    .cfi_offset r14, -40
    push r15
    .cfi_adjust_cfa_offset 8
    .cfi_offset r15, -48
    sub rsp, 16
    .cfi_adjust_cfa_offset 16
    mov r12, rsi                        # owned root
    mov r15d, edx                       # desired order
    test dil, 1
    jnz .Limmediate_limit
    # A heap Nat exceeds the number of nodes addressable by this process.
    call .Ldrop
    mov rdi, -1
.Limmediate_limit:
    shr rdi, 1
    mov r13, r12
    xor ebx, ebx
.Lcount_args:
    cmp rbx, rdi
    je .Lallocate
    cmp byte ptr [r13 + 7], 5
    jne .Lallocate
    mov r13, [r13 + 8]
    inc rbx
    jmp .Lcount_args
.Lallocate:
    lea rdi, [rbx*2 + 1]
    mov esi, 1                          # scalar placeholder, no references
    call lean_mk_array@PLT
    mov r14, rax
    test rbx, rbx
    jz .Lfinish_array
    lea rdx, [r14 + 24]                 # first array slot
    test r15d, r15d
    mov r15d, 8
    jnz .Lstart_fill
    lea rdx, [rdx + rbx*8 - 8]         # last array slot
    neg r15
.Lstart_fill:
    mov r13, r12
    mov [rsp], rbx                      # remaining argument count
    mov rbx, rdx                        # current output slot
.Lfill:
    mov rdi, [r13 + 16]
    mov r13, [r13 + 8]
    call .Lowned_expr
    mov [rbx], rax
    add rbx, r15
    dec qword ptr [rsp]
    jnz .Lfill
.Lfinish_array:
    mov rdi, r12
    call .Ldrop
    mov rax, r14
    add rsp, 16
    .cfi_adjust_cfa_offset -16
    pop r15
    .cfi_restore r15
    .cfi_adjust_cfa_offset -8
    pop r14
    .cfi_restore r14
    .cfi_adjust_cfa_offset -8
    pop r13
    .cfi_restore r13
    .cfi_adjust_cfa_offset -8
    pop r12
    .cfi_restore r12
    .cfi_adjust_cfa_offset -8
    pop rbx
    .cfi_restore rbx
    .cfi_adjust_cfa_offset -8
    ret
    .cfi_endproc

.section .note.GNU-stack,"",@progbits
