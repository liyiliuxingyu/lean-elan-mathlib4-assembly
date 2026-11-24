# SPDX-License-Identifier: Apache-2.0
# Dump the reachable Expr DAG and its universe-level data from a pinned
# Lean 4.19.0 .olean image. IDs are offsets from the start of the file.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ SYS_write, 1
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ EINTR, -4
.equ ROW_BYTES, 16384
.equ ROW_RESERVE, 128
.equ W_COUNT, 0
.equ W_HEAD, 8
.equ W_SLOTS, 16
.equ W_SIZE, 24
.equ W_LEVEL, 32
.equ W_DIGITS, W_LEVEL + 56
.equ W_ROW, 96
.equ W_QUEUE, W_ROW + ROW_BYTES

.equ NODE_EXPR, 0
.equ NODE_LEVEL, 1
.equ NODE_LEVELS, 2

.macro ELAYOUT tag, bytes, fields, description
    .long .Lexpr_\tag - .Lexpressions
    .byte \bytes, \fields, 0, 0
    .pushsection .rodata.expr_tags,"a",@progbits
.Lexpr_\tag:
    .asciz "\tag"
    .asciz "\description"
    .popsection
.endm

.section .rodata
.align 8
.Lexpressions:
    ELAYOUT bvar,      24, 1, i
    ELAYOUT fvar,      24, 1, n
    ELAYOUT mvar,      24, 1, n
    ELAYOUT sort,      24, 1, u
    ELAYOUT const,     32, 2, nl
    ELAYOUT app,       32, 2, ee
    ELAYOUT lam,       48, 3, neeb
    ELAYOUT forallE,   48, 3, neeb
    ELAYOUT letE,      56, 4, neeer
    ELAYOUT lit,       24, 1, t
    ELAYOUT mdata,     32, 2, de
    ELAYOUT proj,      40, 3, nie

.Llevels:
    .long .Lzero - .Llevels
    .long .Lsucc - .Llevels
    .long .Lmax - .Llevels
    .long .Limax - .Llevels
    .long .Lparam - .Llevels
    .long .Lmvar - .Llevels

.Ltype:         .asciz "type"
.Lproof:        .asciz "proof"
.Lexpr:         .asciz "expr"
.Llevel:        .asciz "level"
.Llevel_list:   .asciz "levels"
.Lcons:         .asciz "cons"
.Lzero:         .asciz "zero"
.Lsucc:         .asciz "succ"
.Lmax:          .asciz "max"
.Limax:         .asciz "imax"
.Lparam:        .asciz "param"
.Lmvar:         .asciz "mvar"
.Lnat:          .asciz "nat"
.Lstring:       .asciz "string"

.text
.globl mathlib_olean_dump_term
.type mathlib_olean_dump_term, @function
# rdi = parsed view, rsi = type root offset, rdx = proof root offset.
# stdout receives TSV. Return 0, -1 for unreadable bounds/objects, -2 for
# an output error, or -3 for a work-mapping failure.
mathlib_olean_dump_term:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r14, rsi
    mov rbx, rdx

    mov r8, [r12 + VIEW_SIZE]
    shr r8, 3
    # The work map reserves one qword per possible node offset for the
    # queue and one byte per offset for kind-aware deduplication.
    lea rsi, [r8 + r8*8 + W_QUEUE]
    mov rbp, rsi
    xor edi, edi
    mov edx, 3                   # PROT_READ | PROT_WRITE
    mov r10d, 0x22               # MAP_PRIVATE | MAP_ANONYMOUS
    mov r8d, -1
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    cmp rax, -4095
    jae .Lno_work
    mov r13, rax
    mov [r13 + W_SIZE], rbp
    mov rax, [r12 + VIEW_SIZE]
    shr rax, 3
    mov [r13 + W_SLOTS], rax

    mov rax, r14
    xor ecx, ecx
    call .Lenqueue
    jc .Lbad
    mov rax, rbx
    xor ecx, ecx
    call .Lenqueue
    jc .Lbad

    lea rsi, [rip + .Ltype]
    mov rax, r14
    call .Lrow_header
    call .Lwrite_row
    jc .Loutput
    lea rsi, [rip + .Lproof]
    mov rax, rbx
    call .Lrow_header
    call .Lwrite_row
    jc .Loutput

.Lnext_node:
    mov rax, [r13 + W_HEAD]
    cmp rax, [r13 + W_COUNT]
    jae .Ldone
    inc qword ptr [r13 + W_HEAD]
    mov r14, [r13 + W_QUEUE + rax*8]
    mov ebx, r14d
    and ebx, 7
    and r14, -8
    cmp ebx, NODE_LEVEL
    je .Llevel_node
    cmp ebx, NODE_LEVELS
    je .Llevel_list_node

    mov rax, r14
    mov edx, 8
    call .Loffset_object
    test rax, rax
    jz .Lbad
    movzx ecx, byte ptr [rax + 7]
    cmp ecx, 11
    ja .Lbad
    lea rbx, [rip + .Lexpressions]
    lea rbp, [rbx + rcx*8]
    movzx edx, byte ptr [rbp + 4]
    mov rax, r14
    call .Loffset_object
    test rax, rax
    jz .Lbad
    mov dl, [rbp + 5]
    cmp [rax + 6], dl
    jne .Lbad
    movsxd rbp, dword ptr [rbp]
    add rbp, rbx
    mov rbx, rax
    mov rax, r14
    lea rsi, [rip + .Lexpr]
    call .Lrow_header
    call .Ltab
    mov rsi, rbp
    call .Ltext
    mov rbp, rsi                 # Field description just after the tag name
    add rbx, 8
.Lexpr_field:
    movzx eax, byte ptr [rbp]
    test eax, eax
    jz .Lemit
    inc rbp
    call .Ltab
    mov rsi, [rbx]
    cmp al, 'e'
    je .Lexpr_ref
    cmp al, 'u'
    je .Llevel_ref
    cmp al, 'l'
    je .Llist_ref
    cmp al, 'n'
    je .Lname_field
    cmp al, 'i'
    je .Lnat_field
    cmp al, 't'
    je .Lliteral
    cmp al, 'd'
    je .Lmetadata
    # Last fields for forall, lambda and let are scalar bytes, preceded
    # by the 8-byte cached ExprData. Consume them without copying it.
    movzx edx, byte ptr [rbx + 8]
    cmp al, 'b'
    jne .Lbool_field
    cmp edx, 3
    ja .Lbad
    jmp .Lscalar_field
.Lbool_field:
    cmp edx, 1
    ja .Lbad
.Lscalar_field:
    mov eax, edx
    call .Lnumber
    jmp .Lfield_done

.Lexpr_ref:
    mov ecx, NODE_EXPR
    jmp .Lraw_ref
.Llevel_ref:
    mov ecx, NODE_LEVEL
    jmp .Lraw_ref
.Llist_ref:
    mov ecx, NODE_LEVELS
.Lraw_ref:
    call .Lreference
    jc .Lbad
    jmp .Lfield_done
.Lmetadata:
    xor eax, eax
    cmp rsi, 1
    je .Lmetadata_offset
    mov rdi, r12
    mov edx, 8
    call mathlib_olean_object
    test rax, rax
    jz .Lbad
    sub rax, [r12 + VIEW_MAPPING]
.Lmetadata_offset:
    call .Lnumber
    jmp .Lfield_done

.Lliteral:
    mov rdi, r12
    mov edx, 16
    call mathlib_olean_object
    test rax, rax
    jz .Lbad
    cmp byte ptr [rax + 6], 1
    jne .Lbad
    movzx edx, byte ptr [rax + 7]
    mov [rsp], rax
    test edx, edx
    jnz .Lstring_literal
    lea rsi, [rip + .Lnat]
    call .Ltext
    call .Ltab
    mov rax, [rsp]
    mov rsi, [rax + 8]
    jmp .Lnat_field
.Lstring_literal:
    cmp edx, 1
    jne .Lbad
    lea rsi, [rip + .Lstring]
    call .Ltext
    call .Ltab
    mov rax, [rsp]
    mov rsi, [rax + 8]
    call .Lformat_args
    call mathlib_olean_string_format
    jmp .Lformat_done

.Lnat_field:
    call .Lformat_args
    call mathlib_olean_nat_format
    jmp .Lformat_done
.Lname_field:
    call .Lformat_args
    call mathlib_olean_name_format
.Lformat_done:
    test eax, eax
    js .Lbad
    add r15, rax
.Lfield_done:
    add rbx, 8
    jmp .Lexpr_field

.Llevel_node:
    mov rdi, r12
    mov rsi, r14
    lea rdx, [r13 + W_LEVEL]
    call mathlib_olean_level_node
    cmp eax, 1
    jne .Lbad
    mov rax, r14
    lea rsi, [rip + .Llevel]
    call .Lrow_header
    call .Ltab
    mov rbx, [r13 + W_LEVEL]
    cmp rbx, 5
    ja .Lbad
    lea rsi, [rip + .Llevels]
    movsxd rax, dword ptr [rsi + rbx*4]
    add rsi, rax
    call .Ltext
    test ebx, ebx
    jz .Lemit
    call .Ltab
    cmp ebx, 4
    jae .Llevel_name
    mov rax, [r13 + W_LEVEL + 8]
    call .Llevel_id
    jc .Lbad
    cmp ebx, 1
    je .Lemit
    call .Ltab
    mov rax, [r13 + W_LEVEL + 16]
    call .Llevel_id
    jc .Lbad
    jmp .Lemit
.Llevel_name:
    mov rsi, [r13 + W_LEVEL + 8]
    call .Lformat_args
    call mathlib_olean_name_format
    test eax, eax
    js .Lbad
    add r15, rax
    jmp .Lemit

.Llevel_list_node:
    mov rax, r14
    mov edx, 24
    call .Loffset_object
    test rax, rax
    jz .Lbad
    cmp word ptr [rax + 6], 0x0102   # List.cons, two object fields
    jne .Lbad
    mov rbx, rax
    mov rax, r14
    lea rsi, [rip + .Llevel_list]
    call .Lrow_header
    call .Ltab
    lea rsi, [rip + .Lcons]
    call .Ltext
    call .Ltab
    mov rsi, [rbx + 8]
    mov ecx, NODE_LEVEL
    call .Lreference
    jc .Lbad
    call .Ltab
    mov rsi, [rbx + 16]
    mov ecx, NODE_LEVELS
    call .Lreference
    jc .Lbad

.Lemit:
    call .Lwrite_row
    jc .Loutput
    jmp .Lnext_node

.Ldone:
    xor ebx, ebx
    jmp .Lunmap
.Lbad:
    mov ebx, -1
    jmp .Lunmap
.Loutput:
    mov ebx, -2
.Lunmap:
    mov rdi, r13
    mov rsi, [r13 + W_SIZE]
    mov eax, SYS_munmap
    syscall
    mov eax, ebx
    jmp .Lreturn
.Lno_work:
    mov eax, -3
.Lreturn:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size mathlib_olean_dump_term, .-mathlib_olean_dump_term

# Queue an aligned offset once, and reject conflicting interpretations of
# the same offset as different object kinds. Preserve rax for rendering.
.Lenqueue:
    cmp rax, 96
    jb .Linvalid_carry
    test al, 7
    jnz .Linvalid_carry
    mov rdx, rax
    shr rdx, 3
    mov r9, [r13 + W_SLOTS]
    cmp rdx, r9
    jae .Linvalid_carry
    lea r8, [r13 + W_QUEUE + r9*8]
    inc ecx
    movzx r9d, byte ptr [r8 + rdx]
    test r9d, r9d
    jnz .Lseen
    mov [r8 + rdx], cl
    lea rdx, [rax + rcx - 1]
    mov r8, [r13 + W_COUNT]
    mov [r13 + W_QUEUE + r8*8], rdx
    inc qword ptr [r13 + W_COUNT]
    clc
    ret
.Lseen:
    cmp ecx, r9d
    jne .Linvalid_carry
    clc
    ret

.Linvalid_carry:
    stc
    ret

# Convert the raw child pointer in rsi and emit its normalized ID. The
# boxed value 1 represents a nil level list (or immediate Level.zero).
.Lreference:
    push rcx
    cmp rsi, 1
    jne .Lreference_pointer
    test ecx, ecx
    jz .Lreference_bad
    xor eax, eax
    jmp .Lreference_number
.Lreference_pointer:
    mov rdi, r12
    mov edx, 8
    call mathlib_olean_object
    test rax, rax
    jz .Lreference_bad
    sub rax, [r12 + VIEW_MAPPING]
    # Lean's compactor writes all constructor children before the parent.
    cmp rax, r14
    jae .Lreference_bad
    mov ecx, [rsp]
    call .Lenqueue
    jc .Lreference_bad
.Lreference_number:
    pop rcx
    jmp .Lnumber_success
.Lreference_bad:
    pop rcx
    stc
    ret

.Llevel_id:
    sub rsp, 8
    cmp rax, 1
    jne .Lnonzero_level_id
    xor eax, eax
    jmp .Lfinish_level_id
.Lnonzero_level_id:
    cmp rax, r14
    jae .Lbad_level_id
    mov ecx, NODE_LEVEL
    call .Lenqueue
    jc .Lbad_level_id
.Lfinish_level_id:
    add rsp, 8
    jmp .Lnumber_success
.Lbad_level_id:
    add rsp, 8
    stc
    ret

.Lnumber_success:
    sub rsp, 8
    call .Lnumber
    add rsp, 8
    clc
    ret

.Loffset_object:
    mov rdi, r12
    mov rsi, [r12 + VIEW_BASE]
    add rsi, rax
    jnc mathlib_olean_object
    xor eax, eax
    ret

.Lformat_args:
    mov rdi, r12
    mov rdx, r15
    lea rcx, [r13 + W_ROW + ROW_BYTES - ROW_RESERVE]
    sub rcx, r15
    ret

.Lrow_header:
    lea r15, [r13 + W_ROW]
    sub rsp, 8
    call .Ltext
    call .Ltab
    add rsp, 8
    jmp .Lnumber
.Ltext:
    mov dl, [rsi]
    inc rsi
    test dl, dl
    jz .Ltext_done
    mov [r15], dl
    inc r15
    jmp .Ltext
.Ltext_done:
    ret
.Ltab:
    mov byte ptr [r15], 9
    inc r15
    ret
.Lnumber:
    lea rsi, [r13 + W_DIGITS]
    mov r8, rsi
    mov ecx, 10
.Ldigit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .Ldigit
    mov rcx, r8
    sub rcx, rsi
    mov rdi, r15
    rep movsb
    mov r15, rdi
    ret

.Lwrite_row:
    mov byte ptr [r15], 10
    inc r15
    lea rsi, [r13 + W_ROW]
    mov rdx, r15
    sub rdx, rsi
    mov edi, 1
.Lwrite:
    mov eax, SYS_write
    syscall
    cmp rax, EINTR
    je .Lwrite
    test rax, rax
    jle .Linvalid_carry
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite
    clc
    ret

.section .note.GNU-stack,"",@progbits
