# SPDX-License-Identifier: Apache-2.0
# Standalone System V ABI regression tests for the non-libc++ UTF-8 additions.
.intel_syntax noprefix
.text
.globl _start
.type _start, @function
_start:
    and rsp, -16
    sub rsp, 16          # Hidden return storage for both lean::optional types.

    xor ebx, ebx
.Llead_test:
    mov qword ptr [rsp], -1
    mov rdi, rsp
    mov esi, ebx
    call _ZN4lean23get_utf8_first_byte_optEh
    cmp rax, rsp
    jne .Llead_fail
    mov eax, 1
    cmp ebx, 0x80
    jb .Llead_expect_value
    cmp ebx, 0xc0
    jb .Llead_expect_none
    mov eax, 2
    cmp ebx, 0xe0
    jb .Llead_expect_value
    mov eax, 3
    cmp ebx, 0xf0
    jb .Llead_expect_value
    mov eax, 4
    cmp ebx, 0xf8
    jb .Llead_expect_value
.Llead_expect_none:
    cmp byte ptr [rsp], 0
    jne .Llead_fail
    jmp .Llead_advance
.Llead_expect_value:
    cmp byte ptr [rsp], 1
    jne .Llead_fail
    cmp dword ptr [rsp + 4], eax
    jne .Llead_fail
.Llead_advance:
    inc ebx
    cmp ebx, 256
    jb .Llead_test

    xor ebx, ebx
    lea r12, [rip + .Loffsets]
.Lpos_test:
    mov qword ptr [rsp], -1
    mov qword ptr [rsp + 8], -1
    mov rdi, rsp
    lea rsi, [rip + .Lmixed]
    mov rdx, rbx
    call _ZN4lean13utf8_char_posEPKcm
    cmp rax, rsp
    jne .Lpos_fail
    cmp byte ptr [rsp], 1
    jne .Lpos_fail
    movzx eax, byte ptr [r12 + rbx]
    cmp qword ptr [rsp + 8], rax
    jne .Lpos_fail
    inc ebx
    cmp ebx, 4
    jb .Lpos_test
    mov rdi, rsp
    lea rsi, [rip + .Lmixed]
    mov edx, 4
    call _ZN4lean13utf8_char_posEPKcm
    cmp byte ptr [rsp], 0
    jne .Lpos_fail

    lea rbx, [rip + .Lunicode_cases]
    lea r12, [rip + .Lunicode_cases_end]
.Lunicode_test:
    lea rdi, [rip + .Lunicode_bytes]
    add rdi, [rbx]
    mov rsi, rdi
    add rsi, [rbx + 8]
    call _ZN4lean15utf8_to_unicodeEPKhS1_
    cmp eax, dword ptr [rbx + 16]
    jne .Lunicode_fail
    add rbx, 24
    cmp rbx, r12
    jb .Lunicode_test
    xor edi, edi
    jmp .Lexit
.Llead_fail:
    mov edi, 1
    jmp .Lexit
.Lpos_fail:
    mov edi, 2
    jmp .Lexit
.Lunicode_fail:
    mov edi, 3
.Lexit:
    mov eax, 60
    syscall
.size _start, . - _start

.section .rodata
.Lmixed:
    .byte 'a', 0xc2, 0xa2, 0xe4, 0xb8, 0xad, 0xf0, 0x9f, 0xa6, 0x80, 0
.Loffsets:
    .byte 0, 1, 3, 6
.Lunicode_bytes:
    .byte 'A', 0xc2, 0x41, 0xe4, 0xb8, 0xad, 0xf0, 0x9f, 0xa6, 0x80, 0x9d
.balign 8
.Lunicode_cases:
    .quad 0, 0, 0
    .quad 0, 1, 'A'
    .quad 1, 1, 0           # Truncated two-byte sequence.
    .quad 1, 2, 0x81        # Bounded conversion masks the second byte.
    .quad 3, 2, 0           # Truncated three-byte sequence.
    .quad 3, 3, 0x4e2d
    .quad 6, 3, 0           # Truncated four-byte sequence.
    .quad 6, 4, 0x1f980
    .quad 10, 1, 0x1d       # A bare continuation yields its payload.
.Lunicode_cases_end:

.section .note.GNU-stack,"",@progbits
