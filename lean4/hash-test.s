# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.text
.globl _start
.type _start,@function
_start:
    and rsp, -16
    lea r12, [rip + .Lvectors]
    lea r13, [rip + .Lvectors_end]
    lea r14, [rip + .Lsample]
    mov r15d, 1

.Lcompare:
    mov rdi, QWORD PTR [r12 + 8]
    mov rsi, QWORD PTR [r12]
    add rsi, r14
    mov rdx, QWORD PTR [r12 + 16]
    call _ZN4lean8hash_strEmPKhm
    cmp rax, QWORD PTR [r12 + 24]
    jne .Lfailed
    inc r15d
    add r12, 32
    cmp r12, r13
    jb .Lcompare

    xor edi, edi
    jmp .Lexit
.Lfailed:
    mov edi, r15d
.Lexit:
    mov eax, 60
    syscall
.size _start, . - _start

.section .rodata
.balign 8
.Lsample:
.set sample_index, 0
.rept 96
    .byte (sample_index * 73 + 29) & 255
    .set sample_index, sample_index + 1
.endr

# Offset, size, seed, output from the pinned upstream C++ implementation.
.Lvectors:
    .quad 0, 0, 0x0000000000000000, 0x0000000000000000
    .quad 0, 0, 0x0000000000000001, 0xc6a4a7935bd064dc
    .quad 0, 0, 0xffffffffffffffff, 0xb0d9485c2cd761b2
    .quad 1, 1, 0x0706050403020100, 0x72822320643b01b2
    .quad 1, 2, 0x0706050403020100, 0x010b3a919896fd6e
    .quad 1, 3, 0x0706050403020100, 0xc680f5559fe57249
    .quad 1, 4, 0x0706050403020100, 0x5d8a22c0cd57ec23
    .quad 1, 5, 0x0706050403020100, 0x0b8170aba08d6fc2
    .quad 1, 6, 0x0706050403020100, 0x4c714899592d686a
    .quad 1, 7, 0x0706050403020100, 0xc5c8c3f2ec29d772
    .quad 1, 8, 0x0706050403020100, 0x0c7d36c3dfeddb9b
    .quad 1, 9, 0x0706050403020100, 0x5e6cb6eeac47eaf8
    .quad 1, 10, 0x0706050403020100, 0x3e9c9e0bcc723a1b
    .quad 1, 11, 0x0706050403020100, 0x8fab734b40ebedb4
    .quad 1, 12, 0x0706050403020100, 0xb6e4b285244c513a
    .quad 1, 13, 0x0706050403020100, 0xa7fd9f9a2e19c431
    .quad 1, 14, 0x0706050403020100, 0xaa49d9e10f3ae4ce
    .quad 1, 15, 0x0706050403020100, 0x0bc8253fa02b1195
    .quad 1, 16, 0x0706050403020100, 0x2fa1ba407104c4c4
    .quad 7, 43, 0x0000000000000000, 0xdfa9eee139e485f6
    .quad 3, 64, 0x0000000000000001, 0x65bb58c653fdd4df
    .quad 0, 96, 0xfedcba9876543210, 0x595cbfb33e23c398
.Lvectors_end:

.section .note.GNU-stack,"",@progbits
