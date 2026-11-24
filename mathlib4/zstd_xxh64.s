# SPDX-License-Identifier: Apache-2.0
# XXH64 with seed zero, used by the 32-bit Zstandard content checksum.
.intel_syntax noprefix
.equ PRIME1, 0x9e3779b185ebca87
.equ PRIME2, 0xc2b2ae3d27d4eb4f
.equ PRIME3, 0x165667b19e3779f9
.equ PRIME4, 0x85ebca77c2b2ae63
.equ PRIME5, 0x27d4eb2f165667c5
.text
.macro lane acc, ofs
    mov rax, [rdi+\ofs]
    imul rax, r9
    add \acc, rax
    rol \acc, 31
    imul \acc, r8
.endm
.macro merge acc
    imul \acc, r9
    rol \acc, 31
    imul \acc, r8
    xor rax, \acc
    imul rax, r8
    add rax, r10
.endm
.globl asm_zstd_xxh64
.type asm_zstd_xxh64,@function
asm_zstd_xxh64:
    movabs r8, PRIME1
    movabs r9, PRIME2
    movabs r10, PRIME4
    movabs rax, PRIME5
    cmp rsi, 32
    jb .Lhash_tail
    push rbx
    push r12
    push r13
    push r14
    lea rbx, [r8+r9]
    mov r12, r9
    xor r13d, r13d
    mov r14, r8
    neg r14
    mov rcx, rsi
.Lstripe:
    lane rbx, 0
    lane r12, 8
    lane r13, 16
    lane r14, 24
    add rdi, 32
    sub rcx, 32
    cmp rcx, 32
    jae .Lstripe
    mov rax, rbx
    rol rax, 1
    mov rdx, r12
    rol rdx, 7
    add rax, rdx
    mov rdx, r13
    rol rdx, 12
    add rax, rdx
    mov rdx, r14
    rol rdx, 18
    add rax, rdx
    merge rbx
    merge r12
    merge r13
    merge r14
    pop r14
    pop r13
    pop r12
    pop rbx
.Lhash_tail:
    add rax, rsi
    and esi, 31
.Lhash_qword:
    cmp esi, 8
    jb .Lhash_dword
    mov rdx, [rdi]
    imul rdx, r9
    rol rdx, 31
    imul rdx, r8
    xor rax, rdx
    rol rax, 27
    imul rax, r8
    add rax, r10
    add rdi, 8
    sub esi, 8
    jmp .Lhash_qword
.Lhash_dword:
    movabs r11, PRIME3
    test esi, 4
    jz .Lhash_byte
    mov edx, [rdi]
    imul rdx, r8
    xor rax, rdx
    rol rax, 23
    imul rax, r9
    add rax, r11
    add rdi, 4
    sub esi, 4
.Lhash_byte:
    test esi, esi
    jz .Lavalanche
    movabs r10, PRIME5
.Lbyte_loop:
    movzx edx, byte ptr [rdi]
    imul rdx, r10
    xor rax, rdx
    rol rax, 11
    imul rax, r8
    inc rdi
    dec esi
    jnz .Lbyte_loop
.Lavalanche:
    mov rdx, rax
    shr rdx, 33
    xor rax, rdx
    imul rax, r9
    mov rdx, rax
    shr rdx, 29
    xor rax, rdx
    imul rax, r11
    mov rdx, rax
    shr rdx, 32
    xor rax, rdx
    ret
.size asm_zstd_xxh64,.-asm_zstd_xxh64
.section .note.GNU-stack,"",@progbits
