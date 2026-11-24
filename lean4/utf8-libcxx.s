# Copyright (c) 2014 Microsoft Corporation. All rights reserved.
# Original author: Leonardo de Moura.
# SPDX-License-Identifier: Apache-2.0
# Lean 4 v4.19.0 UTF-8 overloads for its official Linux x86-64 libc++ ABI.

.intel_syntax noprefix

# The stock libc++ string has 24 bytes. Its short form stores size * 2
# in byte zero and data at byte one. Its long form stores size at byte
# eight and the data pointer at byte sixteen. This is not libstdc++.
.macro string_bytes object, data, length
    movzx \length, byte ptr [\object]
    test \length, 1
    jnz .Lstring_long\@
    shr \length, 1
    lea \data, [\object + 1]
    jmp .Lstring_done\@
.Lstring_long\@:
    mov \length, [\object + 8]
    mov \data, [\object + 16]
.Lstring_done\@:
.endm

.text

.globl _ZN4lean11utf8_strlenERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE
.type _ZN4lean11utf8_strlenERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE, @function
_ZN4lean11utf8_strlenERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE:
    string_bytes rdi, rdi, rsi
    jmp lean_utf8_n_strlen@PLT
.size _ZN4lean11utf8_strlenERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE, . - _ZN4lean11utf8_strlenERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE

.globl _ZN4lean9next_utf8ERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERm
.type _ZN4lean9next_utf8ERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERm, @function
_ZN4lean9next_utf8ERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERm:
    mov rdx, rsi
    string_bytes rdi, rdi, rsi
    jmp _ZN4lean9next_utf8EPKcmRm@PLT
.size _ZN4lean9next_utf8ERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERm, . - _ZN4lean9next_utf8ERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERm

.globl _ZN4lean9utf8_trimERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE
.type _ZN4lean9utf8_trimERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE, @function
_ZN4lean9utf8_trimERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE:
    .cfi_startproc
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset rbx, 0
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r12, 0
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r13, 0
    push r14
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r14, 0
    push r15
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r15, 0
    sub rsp, 16
    .cfi_adjust_cfa_offset 16
    mov rbx, rdi
    mov r12, rsi
    string_bytes r12, r13, r14
    xor r15d, r15d
    mov dword ptr [rsp], -1   # First non-space, if any.
    mov dword ptr [rsp + 4], -1  # First byte of the final space run.
.Ltrim_next:
    cmp r15, r14
    jae .Ltrim_construct
    movzx edi, byte ptr [r13 + r15]
    cmp dil, ' '
    jne .Ltrim_nonspace
    cmp dword ptr [rsp + 4], -1
    jne .Ltrim_advance
    mov [rsp + 4], r15d
    jmp .Ltrim_advance
.Ltrim_nonspace:
    cmp dword ptr [rsp], -1
    jne .Ltrim_reset
    mov [rsp], r15d
.Ltrim_reset:
    mov dword ptr [rsp + 4], -1
.Ltrim_advance:
    call _ZN4lean13get_utf8_sizeEh@PLT
    add r15d, eax
    jmp .Ltrim_next
.Ltrim_construct:
    movsxd rdx, dword ptr [rsp]
    mov ecx, [rsp + 4]
    cmp ecx, -1
    cmove ecx, r14d
    sub ecx, edx
    movsxd rcx, ecx
    # libc++ uses this same constructor for substr. In particular,
    # start == -1 for empty/all-space input raises std::out_of_range.
    mov byte ptr [rsp + 8], 0
    lea r8, [rsp + 8]
    mov rdi, rbx
    mov rsi, r12
    call _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEC1ERKS5_mmRKS4_@PLT
    mov rax, rbx
    add rsp, 16
    .cfi_adjust_cfa_offset -16
    pop r15
    .cfi_adjust_cfa_offset -8
    .cfi_restore r15
    pop r14
    .cfi_adjust_cfa_offset -8
    .cfi_restore r14
    pop r13
    .cfi_adjust_cfa_offset -8
    .cfi_restore r13
    pop r12
    .cfi_adjust_cfa_offset -8
    .cfi_restore r12
    pop rbx
    .cfi_adjust_cfa_offset -8
    .cfi_restore rbx
    ret
    .cfi_endproc
.size _ZN4lean9utf8_trimERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE, . - _ZN4lean9utf8_trimERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEE

.globl _ZN4lean11utf8_decodeERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERNS0_6vectorIjNS4_IjEEEE
.type _ZN4lean11utf8_decodeERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERNS0_6vectorIjNS4_IjEEEE, @function
_ZN4lean11utf8_decodeERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERNS0_6vectorIjNS4_IjEEEE:
    .cfi_startproc
    push rbp
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset rbp, 0
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset rbx, 0
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r12, 0
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r13, 0
    push r14
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r14, 0
    push r15
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r15, 0
    sub rsp, 24
    .cfi_adjust_cfa_offset 24
    string_bytes rdi, r12, r13
    mov r14, rsi
    mov qword ptr [rsp], 0  # Byte position passed by reference.
.Ldecode_loop:
    cmp qword ptr [rsp], r13
    jae .Ldecode_return
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call _ZN4lean9next_utf8EPKcmRm@PLT
    # libc++ vector<unsigned> has begin, end, capacity-end pointers.
    mov r10, [r14 + 8]
    mov r11, [r14 + 16]
    cmp r10, r11
    jae .Ldecode_grow
    mov [r10], eax
    add r10, 4
    mov [r14 + 8], r10
    jmp .Ldecode_loop
.Ldecode_grow:
    mov [rsp + 8], eax
    mov rbp, [r14]
    mov rbx, r10
    sub rbx, rbp           # Bytes in the current range.
    mov rcx, rbx
    shr rcx, 2
    inc rcx                # Required element count.
    movabs rdx, 0x3fffffffffffffff  # vector<unsigned>::max_size()
    cmp rcx, rdx
    ja .Ldecode_length_error
    mov r15, r11
    sub r15, rbp
    shr r15, 2
    mov rax, rdx
    shr rax, 1
    cmp r15, rax
    jae .Ldecode_max_capacity
    add r15, r15
    cmp r15, rcx
    cmovb r15, rcx
    jmp .Ldecode_allocate
.Ldecode_max_capacity:
    mov r15, rdx
.Ldecode_allocate:
    shl r15, 2
    mov rdi, r15
    call _Znwm@PLT
    # Copy the old unsigned elements before publishing the new range.
    mov rcx, rbx
    shr rcx, 2
    mov rsi, rbp
    mov rdi, rax
    rep movsd
    mov ecx, [rsp + 8]
    mov [rax + rbx], ecx
    mov [r14], rax
    lea rcx, [rax + rbx + 4]
    mov [r14 + 8], rcx
    lea rcx, [rax + r15]
    mov [r14 + 16], rcx
    test rbp, rbp
    jz .Ldecode_loop
    mov rdi, rbp
    call _ZdlPv@PLT
    jmp .Ldecode_loop
.Ldecode_length_error:
    mov rdi, r14
    call _ZNKSt3__120__vector_base_commonILb1EE20__throw_length_errorEv@PLT
    ud2
.Ldecode_return:
    add rsp, 24
    .cfi_adjust_cfa_offset -24
    pop r15
    .cfi_adjust_cfa_offset -8
    .cfi_restore r15
    pop r14
    .cfi_adjust_cfa_offset -8
    .cfi_restore r14
    pop r13
    .cfi_adjust_cfa_offset -8
    .cfi_restore r13
    pop r12
    .cfi_adjust_cfa_offset -8
    .cfi_restore r12
    pop rbx
    .cfi_adjust_cfa_offset -8
    .cfi_restore rbx
    pop rbp
    .cfi_adjust_cfa_offset -8
    .cfi_restore rbp
    ret
    .cfi_endproc
.size _ZN4lean11utf8_decodeERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERNS0_6vectorIjNS4_IjEEEE, . - _ZN4lean11utf8_decodeERKNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEERNS0_6vectorIjNS4_IjEEEE

.globl _ZN4lean19push_unicode_scalarERNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEEj
.type _ZN4lean19push_unicode_scalarERNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEEj, @function
_ZN4lean19push_unicode_scalarERNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEEj:
    .cfi_startproc
    push rbx
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset rbx, 0
    push r12
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r12, 0
    push r13
    .cfi_adjust_cfa_offset 8
    .cfi_rel_offset r13, 0
    sub rsp, 16
    .cfi_adjust_cfa_offset 16
    mov rbx, rdi
    mov rdi, rsp
    call _ZN4lean19push_unicode_scalarEPcj@PLT
    mov r13d, eax
    xor r12d, r12d
.Lpush_byte:
    mov rdi, rbx
    movsx esi, byte ptr [rsp + r12]
    call _ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE9push_backEc@PLT
    inc r12d
    cmp r12d, r13d
    jb .Lpush_byte
    add rsp, 16
    .cfi_adjust_cfa_offset -16
    pop r13
    .cfi_adjust_cfa_offset -8
    .cfi_restore r13
    pop r12
    .cfi_adjust_cfa_offset -8
    .cfi_restore r12
    pop rbx
    .cfi_adjust_cfa_offset -8
    .cfi_restore rbx
    ret
    .cfi_endproc
.size _ZN4lean19push_unicode_scalarERNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEEj, . - _ZN4lean19push_unicode_scalarERNSt3__112basic_stringIcNS0_11char_traitsIcEENS0_9allocatorIcEEEEj

.section .note.GNU-stack,"",@progbits
