# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "catalog_layout.inc"
.text
.globl catalog_extend
.hidden catalog_extend
.type catalog_extend, @function
# (arena, additional bytes) -> pointer to new space or NULL.
# The caller must retain offsets, as mremap may move existing contents.
catalog_extend:
    mov r8, rdi
    mov r9, [r8+A_USED]
    add r9, rsi
    jc .Lbad
    test r9, r9
    js .Lbad
    mov rax, [r8+A_DATA]
    cmp r9, [r8+A_CAP]
    jbe .Lenough
    mov rdx, [r8+A_CAP]
    add rdx, rdx
    cmp rdx, r9
    cmovb rdx, r9
    add rdx, 4095
    jc .Lbad
    and rdx, -4096
    test rdx, rdx
    jle .Lbad
    mov rsi, [r8+A_CAP]
    test rsi, rsi
    jz .Lnew
    mov rdi, [r8+A_DATA]
    mov r10d, 1                      # MREMAP_MAYMOVE
    mov eax, 25
    syscall
    jmp .Lallocated
.Lnew:
    push r8
    push r9
    mov rsi, rdx
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    pop r9
    pop r8
    mov rdx, rsi
.Lallocated:
    cmp rax, -4095
    jae .Lbad
    mov [r8+A_DATA], rax
    mov [r8+A_CAP], rdx
.Lenough:
    add rax, [r8+A_USED]
    mov [r8+A_USED], r9
    ret
.Lbad:
    xor eax, eax
    ret
.size catalog_extend, .-catalog_extend

.globl catalog_write
.hidden catalog_write
.type catalog_write, @function
# (fd,data,len) -> 0 or -1; handles partial writes and EINTR.
catalog_write:
    test rdx, rdx
    jz .Lwritten
.Lwrite:
    mov eax, 1
    syscall
    cmp rax, -4
    je .Lwrite
    test rax, rax
    jle .Lfailed
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite
.Lwritten:
    xor eax, eax
    ret
.Lfailed:
    mov eax, -1
    ret
.size catalog_write, .-catalog_write
.section .note.GNU-stack,"",@progbits
