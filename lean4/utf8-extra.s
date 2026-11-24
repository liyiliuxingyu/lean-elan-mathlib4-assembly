# Copyright (c) 2014 Microsoft Corporation. All rights reserved.
# Original author: Leonardo de Moura.
# SPDX-License-Identifier: Apache-2.0
# Lean 4 v4.19.0 UTF-8 scalar and optional results, System V AMD64.

.intel_syntax noprefix
.text

.globl _ZN4lean13utf8_char_posEPKcm
.type _ZN4lean13utf8_char_posEPKcm, @function
_ZN4lean13utf8_char_posEPKcm:
    .cfi_startproc
    # rdi = optional<size_t> return storage, rsi = string, rdx = index.
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
    sub rsp, 8
    .cfi_adjust_cfa_offset 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    xor ebx, ebx
.Lpos_next:
    movzx edi, byte ptr [r13 + rbx]
    test edi, edi
    jz .Lpos_none
    test r14, r14
    jz .Lpos_some
    dec r14
    call _ZN4lean13get_utf8_sizeEh@PLT
    mov eax, eax
    add rbx, rax
    jmp .Lpos_next
.Lpos_some:
    mov byte ptr [r12], 1
    mov qword ptr [r12 + 8], rbx
    jmp .Lpos_return
.Lpos_none:
    mov byte ptr [r12], 0
.Lpos_return:
    mov rax, r12
    add rsp, 8
    .cfi_adjust_cfa_offset -8
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
.size _ZN4lean13utf8_char_posEPKcm, . - _ZN4lean13utf8_char_posEPKcm

.globl _ZN4lean15utf8_to_unicodeEPKhS1_
.type _ZN4lean15utf8_to_unicodeEPKhS1_, @function
_ZN4lean15utf8_to_unicodeEPKhS1_:
    xor eax, eax
    cmp rdi, rsi
    je .Lunicode_done
    movzx edx, byte ptr [rdi]
    cmp edx, 0x80
    jb .Lunicode_ascii
    inc rdi
    xor r8d, r8d
    mov r9d, 0x3f
.Lunicode_cont:
    mov r10d, edx
    and r10d, 0xc0
    cmp r10d, 0xc0
    jne .Lunicode_head
    cmp rdi, rsi
    je .Lunicode_truncated
    add dl, dl
    shr r9d, 1
    inc r8d
    shl eax, 6
    movzx r10d, byte ptr [rdi]
    and r10d, 0x3f
    or eax, r10d
    inc rdi
    jmp .Lunicode_cont
.Lunicode_head:
    mov ecx, r8d
    shr edx, cl
    and edx, r9d
    lea ecx, [r8 + r8 * 2]
    add ecx, ecx
    shl edx, cl
    or eax, edx
.Lunicode_done:
    ret
.Lunicode_ascii:
    mov eax, edx
    ret
.Lunicode_truncated:
    xor eax, eax
    ret
.size _ZN4lean15utf8_to_unicodeEPKhS1_, . - _ZN4lean15utf8_to_unicodeEPKhS1_

.globl _ZN4lean23get_utf8_first_byte_optEh
.type _ZN4lean23get_utf8_first_byte_optEh, @function
_ZN4lean23get_utf8_first_byte_optEh:
    # rdi points to optional<unsigned> return storage.
    mov rax, rdi
    movzx esi, sil
    mov edx, 1
    cmp esi, 0x80
    jb .Lfirst_some
    cmp esi, 0xc0
    jb .Lfirst_none
    mov edx, 2
    cmp esi, 0xe0
    jb .Lfirst_some
    mov edx, 3
    cmp esi, 0xf0
    jb .Lfirst_some
    mov edx, 4
    cmp esi, 0xf8
    jae .Lfirst_none
.Lfirst_some:
    mov byte ptr [rax], 1
    mov dword ptr [rax + 4], edx
    ret
.Lfirst_none:
    mov byte ptr [rax], 0
    ret
.size _ZN4lean23get_utf8_first_byte_optEh, . - _ZN4lean23get_utf8_first_byte_optEh

.section .note.GNU-stack,"",@progbits
