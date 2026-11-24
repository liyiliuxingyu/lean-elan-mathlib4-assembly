# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2013 Microsoft Corporation. All rights reserved.
# Original author: Leonardo de Moura. MurmurHash2 by Austin Appleby.
# Hand translation of Lean v4.19.0 src/runtime/hash.cpp for Linux x86-64.
.intel_syntax noprefix

.equ MURMUR_MULTIPLIER, 0xc6a4a7935bd1e995
.equ MURMUR_SHIFT, 47

.text
.globl _ZN4lean8hash_strEmPKhm
.type _ZN4lean8hash_strEmPKhm, @function

# lean::hash_str(size_t len, unsigned char const *str, uint64_t seed)
# SysV: rdi = len, rsi = str, rdx = seed; rax = result.
_ZN4lean8hash_strEmPKhm:
    .cfi_startproc
    movabs r8, MURMUR_MULTIPLIER
    mov rax, rdi
    imul rax, r8
    xor rax, rdx

.Lblock:
    cmp rdi, 8
    jb .Ltail
    mov r9, QWORD PTR [rsi]
    add rsi, 8
    sub rdi, 8
    imul r9, r8
    mov rdx, r9
    shr rdx, MURMUR_SHIFT
    xor r9, rdx
    imul r9, r8
    xor rax, r9
    imul rax, r8
    jmp .Lblock

.Ltail:
    test rdi, rdi
    jz .Lfinal
    xor ecx, ecx
.Ltail_byte:
    shl rcx, 8
    movzx r9d, BYTE PTR [rsi + rdi - 1]
    or rcx, r9
    dec rdi
    jnz .Ltail_byte
    xor rax, rcx
    imul rax, r8

.Lfinal:
    mov rdx, rax
    shr rdx, MURMUR_SHIFT
    xor rax, rdx
    imul rax, r8
    mov rdx, rax
    shr rdx, MURMUR_SHIFT
    xor rax, rdx
    ret
    .cfi_endproc
.size _ZN4lean8hash_strEmPKhm, . - _ZN4lean8hash_strEmPKhm

.section .note.GNU-stack,"",@progbits
