# SPDX-License-Identifier: Apache-2.0
# Loose de Bruijn index shifts, Lean 4.19.0 / System V AMD64.
.intel_syntax noprefix

# Per-call cache. The stack context lives in r14 across recursive visits.
.equ TABLE, 0
.equ CAPACITY, 8
.equ COUNT, 16
.equ CUTOFF, 24
.equ DELTA, 28
.equ LOWER, 32
.equ INLINE_TABLE, 48
.equ INLINE_SLOTS, 16
.equ CONTEXT_BYTES, INLINE_TABLE + INLINE_SLOTS * 24

.section .rodata
# First child offset, child count, zero-based position entering a binder (or 255).
.Llayout:
    .byte 0,0,255,0                    # bvar
    .byte 0,0,255,0                    # fvar
    .byte 0,0,255,0                    # mvar
    .byte 0,0,255,0                    # sort
    .byte 0,0,255,0                    # const
    .byte 8,2,255,0                    # app
    .byte 16,2,1,0                     # lambda
    .byte 16,2,1,0                     # forall
    .byte 16,3,2,0                     # let
    .byte 0,0,255,0                    # literal
    .byte 16,1,255,0                   # metadata
    .byte 24,1,255,0                   # projection

.text
.globl lean_expr_lower_loose_bvars
.type lean_expr_lower_loose_bvars,@function
lean_expr_lower_loose_bvars:
    # Both Nats are borrowed. Upstream compares the full immediate values
    # before narrowing the arguments to C++ unsigned.
    cmp rsi, rdx
    jb .Lretain
    mov ecx, 1
    jmp .Lshift
.size lean_expr_lower_loose_bvars,.-lean_expr_lower_loose_bvars

.globl lean_expr_lift_loose_bvars
.type lean_expr_lift_loose_bvars,@function
lean_expr_lift_loose_bvars:
    xor ecx, ecx
    jmp .Lshift
.size lean_expr_lift_loose_bvars,.-lean_expr_lift_loose_bvars

# Lean closure entries consume all three arguments after the borrowed C call.
.macro boxed public, native
.globl \public
.type \public,@function
\public:
    .cfi_startproc
    push rdi
    .cfi_adjust_cfa_offset 8
    push rsi
    .cfi_adjust_cfa_offset 8
    push rdx
    .cfi_adjust_cfa_offset 8
    call \native
    mov rdi, [rsp]                     # release delta, cutoff, then expression
    mov [rsp], rax
    call .Ldrop_value
    mov rdi, [rsp + 8]
    call .Ldrop_value
    mov rdi, [rsp + 16]
    call .Ldrop
    mov rax, [rsp]
    add rsp, 24
    .cfi_adjust_cfa_offset -24
    ret
    .cfi_endproc
.size \public,.-\public
.endm

boxed l_Lean_Expr_lowerLooseBVars___boxed, lean_expr_lower_loose_bvars
boxed l_Lean_Expr_liftLooseBVars___boxed,  lean_expr_lift_loose_bvars

.Lshift:
    .cfi_startproc
    test sil, 1
    jz .Lretain
    test dl, 1
    jz .Lretain
    shr rdx, 1
    test edx, edx
    jz .Lretain
    shr rsi, 1
    movzx eax, byte ptr [rdi + 6]
    mov rax, [rdi + rax*8 + 8]
    shr rax, 44                        # cached exclusive upper bound
    cmp esi, eax
    jae .Lretain

    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_offset rbx,-16
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_offset r12,-24
    push r14
    .cfi_adjust_cfa_offset 8
    .cfi_offset r14,-32
    sub rsp, CONTEXT_BYTES
    .cfi_adjust_cfa_offset CONTEXT_BYTES
    mov r14, rsp
    mov qword ptr [r14 + TABLE], 0
    mov qword ptr [r14 + CAPACITY], 0
    mov qword ptr [r14 + COUNT], 0
    mov [r14 + CUTOFF], esi
    mov [r14 + DELTA], edx
    mov [r14 + LOWER], ecx
    xor esi, esi
    call .Lvisit
    mov rbx, rax
    xor r12d, r12d
.Lrelease_cache:
    cmp r12, [r14 + CAPACITY]
    jae .Lrelease_table
    lea rax, [r12 + r12*2]
    mov rdx, [r14 + TABLE]
    cmp qword ptr [rdx + rax*8], 0
    je .Lnext_entry
    mov rdi, [rdx + rax*8 + 16]
    call .Ldrop
.Lnext_entry:
    inc r12
    jmp .Lrelease_cache
.Lrelease_table:
    mov rsi, [r14 + CAPACITY]
    cmp rsi, INLINE_SLOTS
    jbe .Lreleased_table
    imul rsi, 24
    mov rdi, [r14 + TABLE]
    mov eax, 11                         # munmap heap-sized slot table
    syscall
.Lreleased_table:
    mov rax, rbx
    add rsp, CONTEXT_BYTES
    .cfi_adjust_cfa_offset -CONTEXT_BYTES
    pop r14
    .cfi_restore r14
    .cfi_adjust_cfa_offset -8
    pop r12
    .cfi_restore r12
    .cfi_adjust_cfa_offset -8
    pop rbx
    .cfi_restore rbx
    .cfi_adjust_cfa_offset -8
    ret
    .cfi_endproc

# Visit borrowed node rdi at depth esi. Return one owned expression.
.Lvisit:
    .cfi_startproc
    push rbp
    .cfi_adjust_cfa_offset 8
    .cfi_offset rbp,-16
    mov rbp, rsp
    .cfi_def_cfa_register rbp
    push rbx
    .cfi_offset rbx,-24
    push r12
    .cfi_offset r12,-32
    push r13
    .cfi_offset r13,-40
    push r15
    .cfi_offset r15,-48
    sub rsp, 32                        # 3 owned child results, cache flag, change flag
    mov r12, rdi
    mov r13d, esi
    mov dword ptr [rsp + 24], 0
    mov eax, [r12]
    cmp eax, 1                         # likely unshared ST or MT, as in expr.h
    je .Lfilter
    cmp eax, -1
    je .Lfilter
    mov dword ptr [rsp + 24], 1
    cmp qword ptr [r14 + CAPACITY], 0
    je .Lfilter
    call .Lslot
    cmp qword ptr [rax], 0
    je .Lfilter
    mov rdi, [rax + 16]
    call .Lretain
    jmp .Lreturn
.Lfilter:
    mov edx, [r14 + CUTOFF]
    add edx, r13d
    jc .Lsame
    movzx eax, byte ptr [r12 + 6]
    mov rax, [r12 + rax*8 + 8]
    shr rax, 44
    cmp edx, eax
    jae .Lsame
    movzx eax, byte ptr [r12 + 7]
    test eax, eax
    jz .Lbvar
    lea r15, [rip + .Llayout]
    lea r15, [r15 + rax*4]
    xor ebx, ebx
    mov dword ptr [rsp + 28], 0
.Lchild:
    cmp bl, [r15 + 1]
    je .Lchildren_done
    movzx eax, byte ptr [r15]
    lea rax, [rax + rbx*8]
    mov rdi, [r12 + rax]
    xor esi, esi
    cmp bl, [r15 + 2]
    sete sil
    add esi, r13d
    call .Lvisit
    mov [rsp + rbx*8], rax
    movzx edx, byte ptr [r15]
    lea rdx, [rdx + rbx*8]
    cmp rax, [r12 + rdx]
    je .Lchild_unchanged
    mov dword ptr [rsp + 28], 1
.Lchild_unchanged:
    inc ebx
    jmp .Lchild
.Lchildren_done:
    cmp dword ptr [rsp + 28], 0
    jne .Lrebuild
.Ldiscard_children:
    test ebx, ebx
    jz .Lsame
    dec ebx
    mov rdi, [rsp + rbx*8]
    call .Ldrop
    jmp .Ldiscard_children
.Lsame:
    mov rdi, r12
    call .Lretain
    jmp .Lsave

.Lbvar:
    mov rdi, [r12 + 8]                 # Nat, borrowed from the BVar node
    mov esi, [r14 + DELTA]
    test dil, 1
    jz .Lbig_index
    shr rdi, 1
    cmp rdi, rdx
    jb .Lsame
    cmp dword ptr [r14 + LOWER], 0
    jne .Lsubtract
    add rdi, rsi
    jns .Lbox_index
    call lean_big_uint64_to_nat@PLT    # index crossed the immediate Nat boundary
    jmp .Lmake_index
.Lsubtract:
    sub rdi, rsi
    jae .Lbox_index
    xor edi, edi                       # Nat.sub saturates at 0
.Lbox_index:
    lea rax, [rdi*2 + 1]
    jmp .Lmake_index
.Lbig_index:
    lea rsi, [rsi*2 + 1]
    cmp dword ptr [r14 + LOWER], 0
    jne .Lbig_subtract
    call lean_nat_big_add@PLT
    jmp .Lmake_index
.Lbig_subtract:
    call lean_nat_big_sub@PLT
.Lmake_index:
    mov rdi, rax
    call lean_expr_mk_bvar@PLT
    jmp .Lsave

.Lrebuild:
    cmp byte ptr [r12 + 7], 5
    jne .Lnamed
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    call lean_expr_mk_app@PLT
    jmp .Lsave
.Lnamed:
    mov rdi, [r12 + 8]                 # name or metadata, may be scalar
    call .Lretain
    mov rdi, rax
    mov rsi, [rsp]
    movzx eax, byte ptr [r12 + 7]
    cmp eax, 10
    je .Lmetadata
    cmp eax, 11
    je .Lprojection
    mov rdx, [rsp + 8]
    cmp eax, 8
    je .Llet
    movzx ecx, byte ptr [r12 + 40]     # stored BinderInfo
    cmp eax, 6
    jne .Lforall
    call lean_expr_mk_lambda@PLT
    jmp .Lsave
.Lforall:
    call lean_expr_mk_forall@PLT
    jmp .Lsave
.Llet:
    mov rcx, [rsp + 16]
    call lean_expr_mk_let@PLT          # kernel update_let resets nondep to false
    jmp .Lsave
.Lmetadata:
    call lean_expr_mk_mdata@PLT
    jmp .Lsave
.Lprojection:
    mov rbx, rdi
    mov rdi, [r12 + 16]
    call .Lretain
    mov rsi, rax
    mov rdi, rbx
    mov rdx, [rsp]
    call lean_expr_mk_proj@PLT
.Lsave:
    cmp dword ptr [rsp + 24], 0
    je .Lreturn
    mov r15, rax
    mov rax, [r14 + COUNT]
    add rax, rax
    cmp rax, [r14 + CAPACITY]
    jb .Linsert
    call .Lgrow
.Linsert:
    mov rdi, r12
    mov esi, r13d
    call .Lslot
    mov [rax], r12
    mov [rax + 8], r13d
    mov [rax + 16], r15
    inc qword ptr [r14 + COUNT]
    mov rdi, r15
    call .Lretain                      # cache and caller each own one reference
.Lreturn:
    add rsp, 32
    pop r15
    .cfi_restore r15
    pop r13
    .cfi_restore r13
    pop r12
    .cfi_restore r12
    pop rbx
    .cfi_restore rbx
    pop rbp
    .cfi_restore rbp
    .cfi_def_cfa rsp,8
    ret
    .cfi_endproc

# Find an existing or empty slot for (input pointer, binder depth), rdi/esi.
.Lslot:
    mov rdx, rdi
    shr rdx, 3
    imul eax, esi, 0x9e3779b9
    xor rdx, rax
    mov rax, rdx
    shr rax, 23
    xor rdx, rax
    mov r8, [r14 + CAPACITY]
    dec r8
    mov r9, [r14 + TABLE]
.Lprobe:
    and rdx, r8
    lea rax, [rdx + rdx*2]
    lea rax, [r9 + rax*8]              # 24-byte slot
    cmp qword ptr [rax], 0
    je .Llocated
    cmp [rax], rdi
    jne .Ladvance
    cmp [rax + 8], esi
    je .Llocated
.Ladvance:
    inc rdx
    jmp .Lprobe
.Llocated:
    ret

# Rehash without changing any Lean references or allocating Lean objects.
.Lgrow:
    .cfi_startproc
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_offset rbx,-16
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_offset r12,-24
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_offset r13,-32
    mov rbx, [r14 + TABLE]
    mov r12, [r14 + CAPACITY]
    test r12, r12
    jnz .Lallocate
    # Most shared walks fit in 16 slots. The inline table belongs to the
    # top-level call and is initialized only on its first insertion.
    lea rdi, [r14 + INLINE_TABLE]
    xor eax, eax
    mov ecx, INLINE_SLOTS * 3
    rep stosq
    lea rax, [r14 + INLINE_TABLE]
    mov r13d, INLINE_SLOTS
    jmp .Lpublish
.Lallocate:
    lea r13, [r12 + r12]
    mov eax, 128                         # make use of the first mapped page
    cmp r13, rax
    cmovb r13, rax
    imul rsi, r13, 24
    jo .Lout_of_memory
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9                           # mmap supplies zeroed slots
    syscall
    cmp rax, -4095
    jae .Lout_of_memory
.Lpublish:
    mov [r14 + TABLE], rax
    mov [r14 + CAPACITY], r13
    mov r13, rbx
.Lmove:
    test r12, r12
    jz .Lmoved
    mov rdi, [r13]
    test rdi, rdi
    jz .Lnext_slot
    mov esi, [r13 + 8]
    call .Lslot
    mov [rax], rdi
    mov [rax + 8], esi
    mov rdx, [r13 + 16]
    mov [rax + 16], rdx
.Lnext_slot:
    add r13, 24
    dec r12
    jmp .Lmove
.Lout_of_memory:
    call lean_internal_panic_out_of_memory@PLT
    ud2
.Lmoved:
    test rbx, rbx
    jz .Lgrown
    lea rax, [r14 + INLINE_TABLE]
    cmp rbx, rax
    je .Lgrown
    mov rsi, r13                         # end of old table after rehash
    sub rsi, rbx
    mov rdi, rbx
    mov eax, 11
    syscall
.Lgrown:
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

.Lretain:
    .cfi_startproc
    mov rax, rdi
    test dil, 1
    jnz .Lkept
    cmp dword ptr [rdi], 0
    je .Lkept
    jl .Lkeep_atomic
    inc dword ptr [rdi]
.Lkept:
    ret
.Lkeep_atomic:
    push rdi
    .cfi_adjust_cfa_offset 8
    call lean_inc_ref_cold@PLT
    pop rax
    .cfi_adjust_cfa_offset -8
    ret
    .cfi_endproc

.Ldrop_value:
    test dil, 1
    jnz .Lreleased
.Ldrop:
    cmp dword ptr [rdi], 1
    jg .Ldec_local
    cmp dword ptr [rdi], 0
    jne lean_dec_ref_cold@PLT
.Lreleased:
    ret
.Ldec_local:
    dec dword ptr [rdi]
    ret

.section .note.GNU-stack,"",@progbits
