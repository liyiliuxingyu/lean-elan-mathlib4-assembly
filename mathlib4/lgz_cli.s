# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.section .rodata
.Lusage: .ascii "usage: mathlib-lgz INPUT.lgz > OUTPUT.olean\n"
.equ USAGE_LEN, .-.Lusage
.Lbad: .ascii "mathlib-lgz: unreadable input or invalid LGZ stream\n"
.equ BAD_LEN, .-.Lbad
.Lwrite: .ascii "mathlib-lgz: output error\n"
.equ WRITE_LEN, .-.Lwrite
.text
.globl _start
.type _start,@function
_start:
    cmp qword ptr [rsp], 2
    jne .Lusage_error
    mov edi, -100
    mov rsi, [rsp+16]
    mov edx, 0x80800                # O_RDONLY | O_NONBLOCK | O_CLOEXEC
    xor r10d, r10d
.Lopen:
    mov eax, 257
    syscall
    cmp rax, -4
    je .Lopen
    test eax, eax
    js .Linput_error
    mov ebx, eax
    sub rsp, 144
.Lstat:
    mov edi, ebx
    mov rsi, rsp
    mov eax, 5
    syscall
    cmp rax, -4
    je .Lstat
    test eax, eax
    js .Linput_error
    mov eax, [rsp+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Linput_error
    mov r13, [rsp+48]
    test r13, r13
    jle .Linput_error
    xor edi, edi
    mov rsi, r13
    mov edx, 1
    mov r10d, 2
    mov r8d, ebx
    xor r9d, r9d
    mov eax, 9
    syscall
    cmp rax, -4095
    jae .Linput_error
    mov r12, rax
    mov edi, ebx
    mov eax, 3
    syscall
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    lea rcx, [rsp+8]
    call lgz_decode
    test eax, eax
    jnz .Linput_error
    mov rdi, r12
    mov rsi, r13
    mov eax, 11
    syscall
    mov rsi, [rsp]
    mov rdx, [rsp+8]
    mov edi, 1
.Lstdout:
    mov eax, 1
    syscall
    cmp rax, -4
    je .Lstdout
    test rax, rax
    jle .Loutput_error
    add rsi, rax
    sub rdx, rax
    jnz .Lstdout
    xor edi, edi
    jmp .Lexit
.Lusage_error:
    lea rsi, [rip+.Lusage]
    mov edx, USAGE_LEN
    jmp .Lreport
.Linput_error:
    lea rsi, [rip+.Lbad]
    mov edx, BAD_LEN
    jmp .Lreport
.Loutput_error:
    lea rsi, [rip+.Lwrite]
    mov edx, WRITE_LEN
.Lreport:
    mov edi, 2
    mov eax, 1
    syscall
    mov edi, 2
.Lexit:
    mov eax, 60
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
