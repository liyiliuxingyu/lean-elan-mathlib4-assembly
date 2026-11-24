# Copyright (c) 2014 Microsoft Corporation. All rights reserved.
# Original author: Leonardo de Moura.
# SPDX-License-Identifier: Apache-2.0
# Assembly adaptation of Lean 4 v4.19.0, src/runtime/utf8.cpp.
# Linux x86-64, System V ABI; Intel syntax for GNU as.

.intel_syntax noprefix

.section .rodata
.Lutf8_widths:
    .fill 192, 1, 1    # 00..bf: ASCII or continuation
    .fill 32, 1, 2     # c0..df
    .fill 16, 1, 3     # e0..ef
    .fill 8, 1, 4      # f0..f7
    .fill 4, 1, 5      # f8..fb
    .fill 2, 1, 6      # fc..fd
    .fill 2, 1, 1      # fe..ff: invalid

.text
.globl _ZN4lean12is_utf8_nextEh
.type _ZN4lean12is_utf8_nextEh, @function
_ZN4lean12is_utf8_nextEh:
    xor eax, eax
    and dil, 0xc0
    cmp dil, 0x80
    sete al
    ret
.size _ZN4lean12is_utf8_nextEh, . - _ZN4lean12is_utf8_nextEh

.globl _ZN4lean13get_utf8_sizeEh
.type _ZN4lean13get_utf8_sizeEh, @function
_ZN4lean13get_utf8_sizeEh:
    movzx edi, dil
    lea rax, [rip + .Lutf8_widths]
    movzx eax, byte ptr [rax + rdi]
    ret
.size _ZN4lean13get_utf8_sizeEh, . - _ZN4lean13get_utf8_sizeEh

.globl lean_utf8_strlen
.globl _ZN4lean11utf8_strlenEPKc
.type lean_utf8_strlen, @function
.type _ZN4lean11utf8_strlenEPKc, @function
lean_utf8_strlen:
_ZN4lean11utf8_strlenEPKc:
    lea rcx, [rip + .Lutf8_widths]
    xor eax, eax
.Lstrlen_next:
    movzx edx, byte ptr [rdi]
    test edx, edx
    jz .Lstrlen_done
    movzx edx, byte ptr [rcx + rdx]
    add rdi, rdx
    inc rax
    jmp .Lstrlen_next
.Lstrlen_done:
    ret
.size lean_utf8_strlen, . - lean_utf8_strlen
.size _ZN4lean11utf8_strlenEPKc, . - _ZN4lean11utf8_strlenEPKc

.globl lean_utf8_n_strlen
.globl _ZN4lean11utf8_strlenEPKcm
.type lean_utf8_n_strlen, @function
.type _ZN4lean11utf8_strlenEPKcm, @function
lean_utf8_n_strlen:
_ZN4lean11utf8_strlenEPKcm:
    lea rcx, [rip + .Lutf8_widths]
    xor eax, eax
    xor r8d, r8d
.Ln_strlen_next:
    cmp r8, rsi
    jae .Ln_strlen_done
    movzx edx, byte ptr [rdi + r8]
    movzx edx, byte ptr [rcx + rdx]
    add r8, rdx
    inc rax
    jmp .Ln_strlen_next
.Ln_strlen_done:
    ret
.size lean_utf8_n_strlen, . - lean_utf8_n_strlen
.size _ZN4lean11utf8_strlenEPKcm, . - _ZN4lean11utf8_strlenEPKcm

.globl _ZN4lean18get_utf8_last_charEPKc
.type _ZN4lean18get_utf8_last_charEPKc, @function
_ZN4lean18get_utf8_last_charEPKc:
    # Same precondition as upstream: a nonempty NUL-terminated string.
    lea rcx, [rip + .Lutf8_widths]
.Llast_next:
    mov rax, rdi
    movzx edx, byte ptr [rdi]
    movzx edx, byte ptr [rcx + rdx]
    add rdi, rdx
    cmp byte ptr [rdi], 0
    jne .Llast_next
    ret
.size _ZN4lean18get_utf8_last_charEPKc, . - _ZN4lean18get_utf8_last_charEPKc

.globl _ZN4lean9next_utf8EPKcmRm
.type _ZN4lean9next_utf8EPKcmRm, @function
_ZN4lean9next_utf8EPKcmRm:
    # rdi = str, rsi = size, rdx = &i, with i < size.
    # This decoder uses the low 6 bits of each following byte. The strict
    # continuation-byte checks belong to validate_utf8_one.
    mov r8, [rdx]
    add rdi, r8
    sub rsi, r8
    movzx r9d, byte ptr [rdi]
    cmp r9d, 0x80
    jb .Ldecode_one
    cmp r9d, 0xc2
    jb .Ldecode_one
    cmp r9d, 0xe0
    jb .Ldecode_two
    cmp r9d, 0xf0
    jb .Ldecode_three
    cmp r9d, 0xf4
    ja .Ldecode_one
    cmp rsi, 4
    jb .Ldecode_one
    mov eax, r9d
    and eax, 0x07
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3f
    shl eax, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0x3f
    shl eax, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + 3]
    and ecx, 0x3f
    shl eax, 6
    or eax, ecx
    cmp eax, 0x10000
    jb .Ldecode_one
    cmp eax, 0x10ffff
    ja .Ldecode_one
    add r8, 4
    jmp .Ldecode_done
.Ldecode_three:
    cmp rsi, 3
    jb .Ldecode_one
    mov eax, r9d
    and eax, 0x0f
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3f
    shl eax, 6
    or eax, ecx
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0x3f
    shl eax, 6
    or eax, ecx
    cmp eax, 0x800
    jb .Ldecode_one
    lea ecx, [eax - 0xd800]
    cmp ecx, 0x800
    jb .Ldecode_one
    add r8, 3
    jmp .Ldecode_done
.Ldecode_two:
    cmp rsi, 2
    jb .Ldecode_one
    mov eax, r9d
    and eax, 0x1f
    shl eax, 6
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0x3f
    or eax, ecx
    add r8, 2
    jmp .Ldecode_done
.Ldecode_one:
    mov eax, r9d
    inc r8
.Ldecode_done:
    mov [rdx], r8
    ret
.size _ZN4lean9next_utf8EPKcmRm, . - _ZN4lean9next_utf8EPKcmRm

.globl _ZN4lean17validate_utf8_oneEPKhmRm
.type _ZN4lean17validate_utf8_oneEPKhmRm, @function
_ZN4lean17validate_utf8_oneEPKhmRm:
    # rdi = str, rsi = size, rdx = &pos, with pos < size.
    # Keep the caller's position unchanged until the whole scalar is valid.
    mov r8, [rdx]
    sub rsi, r8
    add rdi, r8
    movzx r9d, byte ptr [rdi]
    cmp r9d, 0x80
    jb .Lvalid_one
    cmp r9d, 0xc2
    jb .Linvalid
    cmp r9d, 0xe0
    jb .Lvalid_two
    cmp r9d, 0xf0
    jb .Lvalid_three
    cmp r9d, 0xf4
    ja .Linvalid
    cmp rsi, 4
    jb .Linvalid

    movzx ecx, byte ptr [rdi + 1]
    cmp r9d, 0xf0
    jne .Lfour_check_upper
    cmp ecx, 0x90
    jb .Linvalid
.Lfour_check_upper:
    cmp r9d, 0xf4
    jne .Lfour_continuations
    cmp ecx, 0x90
    jae .Linvalid
.Lfour_continuations:
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    movzx ecx, byte ptr [rdi + 3]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    add r8, 4
    jmp .Lvalid_done

.Lvalid_three:
    cmp rsi, 3
    jb .Linvalid
    movzx ecx, byte ptr [rdi + 1]
    cmp r9d, 0xe0
    jne .Lthree_check_surrogates
    cmp ecx, 0xa0
    jb .Linvalid
.Lthree_check_surrogates:
    cmp r9d, 0xed
    jne .Lthree_continuations
    cmp ecx, 0xa0
    jae .Linvalid
.Lthree_continuations:
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    movzx ecx, byte ptr [rdi + 2]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    add r8, 3
    jmp .Lvalid_done

.Lvalid_two:
    cmp rsi, 2
    jb .Linvalid
    movzx ecx, byte ptr [rdi + 1]
    and ecx, 0xc0
    cmp ecx, 0x80
    jne .Linvalid
    add r8, 2
    jmp .Lvalid_done

.Lvalid_one:
    inc r8
.Lvalid_done:
    mov [rdx], r8
    mov eax, 1
    ret
.Linvalid:
    xor eax, eax
    ret
.size _ZN4lean17validate_utf8_oneEPKhmRm, . - _ZN4lean17validate_utf8_oneEPKhmRm

.globl _ZN4lean13validate_utf8EPKhmRmS2_
.type _ZN4lean13validate_utf8EPKhmRmS2_, @function
_ZN4lean13validate_utf8EPKhmRmS2_:
    # rdi = str, rsi = size, rdx = &pos, rcx = &i.
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
.Lvalidate_next:
    cmp [r14], r13
    jae .Lvalidate_all
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call _ZN4lean17validate_utf8_oneEPKhmRm
    test al, al
    jz .Lvalidate_return
    inc qword ptr [r15]
    jmp .Lvalidate_next
.Lvalidate_all:
    mov eax, 1
.Lvalidate_return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.size _ZN4lean13validate_utf8EPKhmRmS2_, . - _ZN4lean13validate_utf8EPKhmRmS2_

.globl _ZN4lean19push_unicode_scalarEPcj
.type _ZN4lean19push_unicode_scalarEPcj, @function
_ZN4lean19push_unicode_scalarEPcj:
    cmp esi, 0x80
    jb .Lpush_one
    cmp esi, 0x800
    jb .Lpush_two
    cmp esi, 0x10000
    jb .Lpush_three
    mov eax, esi
    shr eax, 18
    and eax, 0x07
    or al, 0xf0
    mov [rdi], al
    mov eax, esi
    shr eax, 12
    and eax, 0x3f
    or al, 0x80
    mov [rdi + 1], al
    mov eax, esi
    shr eax, 6
    and eax, 0x3f
    or al, 0x80
    mov [rdi + 2], al
    and esi, 0x3f
    or sil, 0x80
    mov [rdi + 3], sil
    mov eax, 4
    ret
.Lpush_three:
    mov eax, esi
    shr eax, 12
    or al, 0xe0
    mov [rdi], al
    mov eax, esi
    shr eax, 6
    and eax, 0x3f
    or al, 0x80
    mov [rdi + 1], al
    and esi, 0x3f
    or sil, 0x80
    mov [rdi + 2], sil
    mov eax, 3
    ret
.Lpush_two:
    mov eax, esi
    shr eax, 6
    or al, 0xc0
    mov [rdi], al
    and esi, 0x3f
    or sil, 0x80
    mov [rdi + 1], sil
    mov eax, 2
    ret
.Lpush_one:
    mov [rdi], sil
    mov eax, 1
    ret
.size _ZN4lean19push_unicode_scalarEPcj, . - _ZN4lean19push_unicode_scalarEPcj

.section .note.GNU-stack,"",@progbits
