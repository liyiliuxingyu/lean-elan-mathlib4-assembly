# SPDX-License-Identifier: Apache-2.0
# Exercise the dictionary API and literal sections, including exact bitstream
# consumption. Expected literals in the FSE case were verified with libzstd.
.intel_syntax noprefix
.section .rodata
.Ltree:
    .byte 128, 0x10               # symbols 0 and 1, both one-bit codes
.Lraw:
    .byte 0x20
    .ascii "Zstd"
.Lrle:
    .byte 0x45, 0, 0xab           # two-byte size encoding
.Lsingle:
    .byte 0x42, 0xc0, 0, 0x80, 0x10, 0x15
.Lfour:
    .byte 0x77, 0x80, 2           # 7 literals, four streams, treeless
    .short 1, 1, 1
    .byte 5, 6, 4, 3
.Lbad_jump:
    .byte 0x77, 0x80, 2
    .short 1, 4, 1                # advertised streams extend past the section
    .byte 5, 6, 4, 3
.Lextra_bits:
    .byte 0x43, 0x40, 0, 0x35    # one excess unused payload bit
.Lno_marker:
    .byte 0x43, 0x40, 0, 0
.Lbad_tree:
    .byte 0x42, 0xc0, 0, 0x80, 0x00, 0x15
.Lfse:
    .byte 0x62, 0x40, 0x07, 0x16, 0x20, 0x90, 0x69, 0x0f
    .byte 0x50, 0x7d, 0x6a, 0x3a, 0xa6, 0x20, 0x93, 0x32
    .byte 0xc2, 0xab, 0x92, 0xca, 0xbf, 0x34, 0x5b, 0x5d
    .byte 0x28, 0x25, 0x01, 0xd1, 0x47, 0xf0, 0x01, 0x02
.Lrle_expected:
    .fill 4, 1, 0xab
.Lsingle_expected:
    .byte 0, 1, 0, 1
.Lfour_expected:
    .byte 0, 1, 1, 0, 0, 0, 1
.Lfse_expected:
    .byte 0, 0x41, 6, 0x3b, 0x22, 1

# {input, input size, destination capacity, expected consumed, output, length}
.p2align 3
.Lcases:
    .quad .Lraw, 5, 4, 5, .Lraw + 1, 4
    .quad .Lrle, 3, 4, 3, .Lrle_expected, 4
    .quad .Lraw, 5, 3, -1, 0, 0
    .quad .Lfour, 13, 7, 13, .Lfour_expected, 7
    .quad .Lsingle, 6, 4, 6, .Lsingle_expected, 4
    .quad .Lfour, 13, 7, 13, .Lfour_expected, 7
    .quad .Lbad_jump, 13, 7, -1, 0, 0
    .quad .Lextra_bits, 4, 4, -1, 0, 0
    .quad .Lno_marker, 4, 4, -1, 0, 0
    .quad .Lbad_tree, 6, 4, -1, 0, 0
    .quad .Lfse, 31, 6, -1, 0, 0
    .quad .Lfse, 32, 6, 32, .Lfse_expected, 6
.Lend_cases:

.bss
.p2align 3
.Lctx:      .skip 4104
.Lproduced: .skip 8
.Lout:      .skip 8

.text
.globl _start
.type _start,@function
_start:
    # A treeless first block requires an initialized dictionary tree.
    lea rdi, [rip + .Lctx]
    lea rsi, [rip + .Lfour]
    mov edx, 13
    lea rcx, [rip + .Lout]
    mov r8d, 7
    lea r9, [rip + .Lproduced]
    call zstd_literals
    cmp rax, -1
    jne .Lfail
    lea rdi, [rip + .Lctx]
    lea rsi, [rip + .Ltree]
    mov edx, 2
    call zstd_huff_tree
    cmp rax, 2
    jne .Lfail

    lea rbx, [rip + .Lcases]
    lea r12, [rip + .Lend_cases]
.Lcase:
    lea rdi, [rip + .Lctx]
    mov rsi, [rbx]
    mov rdx, [rbx + 8]
    lea rcx, [rip + .Lout]
    mov r8, [rbx + 16]
    lea r9, [rip + .Lproduced]
    mov qword ptr [r9], -1
    call zstd_literals
    cmp rax, [rbx + 24]
    jne .Lfail
    cmp rax, -1
    je .Lcheck_error
    mov rcx, [rbx + 40]
    cmp rcx, [rip + .Lproduced]
    jne .Lfail
    mov rsi, [rbx + 32]
    lea rdi, [rip + .Lout]
    repe cmpsb
    jne .Lfail
    jmp .Lnext
.Lcheck_error:
    cmp qword ptr [rip + .Lproduced], -1
    jne .Lfail
.Lnext:
    add rbx, 48
    cmp rbx, r12
    jb .Lcase
    xor edi, edi
    jmp .Lexit
.Lfail:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall
.size _start, .-_start
.section .note.GNU-stack,"",@progbits
