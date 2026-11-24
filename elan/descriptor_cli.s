# SPDX-License-Identifier: Apache-2.0 OR MIT
.intel_syntax noprefix

.equ SYS_write, 1
.equ SYS_exit, 60
.equ EINTR, 4

.section .rodata
.Llocal:
    .ascii "local "
.Llocal_end:
.Lremote:
    .ascii "remote "
.Lremote_end:
.Lpath:
    .ascii "path "
.Lpath_end:
.Linvalid:
    .ascii "invalid\n"
.Linvalid_end:
.Lusage:
    .ascii "Usage: elan-asm-descriptor {parse|dir} <descriptor>\n"
.Lusage_end:
.Lspace:
    .ascii " "
.Lnewline:
    .ascii "\n"

.text
.globl _start
.type _start, @function
_start:
    cmp QWORD PTR [rsp], 3
    jne .Lprint_usage

    mov rbx, QWORD PTR [rsp + 16]
    mov r12, QWORD PTR [rsp + 24]
    xor r13d, r13d

.Lmeasure:
    cmp BYTE PTR [r12 + r13], 0
    je .Lcheck_mode
    inc r13
    jmp .Lmeasure

.Lcheck_mode:
    # Read the NUL-terminated command string only as far as needed.
    cmp BYTE PTR [rbx], 'p'
    je .Lcheck_parse
    cmp BYTE PTR [rbx], 'd'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 1], 'i'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 2], 'r'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 3], 0
    jne .Lprint_usage

    # Decoding can only shorten the descriptor.
    lea rax, [r13 + 15]
    and rax, -16
    sub rsp, rax
    sub rsp, 48
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rsp + 48]
    mov rcx, r13
    mov r8, rsp
    call elan_parse_toolchain_dir
    jmp .Lprint_result

.Lcheck_parse:
    cmp BYTE PTR [rbx + 1], 'a'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 2], 'r'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 3], 's'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 4], 'e'
    jne .Lprint_usage
    cmp BYTE PTR [rbx + 5], 0
    jne .Lprint_usage

.Lparse:
    sub rsp, 48
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call elan_parse_resolved
.Lprint_result:
    cmp eax, 1
    je .Lprint_local
    cmp eax, 2
    je .Lprint_remote
    cmp eax, 3
    je .Lprint_path

    mov edi, 2
    lea rsi, [rip + .Linvalid]
    mov edx, .Linvalid_end - .Linvalid
    call .Lwrite_all
    mov edi, 1
    jmp .Lexit

.Lprint_local:
    lea rsi, [rip + .Llocal]
    mov edx, .Llocal_end - .Llocal
    jmp .Lprint_first

.Lprint_remote:
    lea rsi, [rip + .Lremote]
    mov edx, .Lremote_end - .Lremote
    jmp .Lprint_first

.Lprint_path:
    lea rsi, [rip + .Lpath]
    mov edx, .Lpath_end - .Lpath

.Lprint_first:
    mov edi, 1
    call .Lwrite_all
    mov rsi, QWORD PTR [rsp + 8]
    mov rdx, QWORD PTR [rsp + 16]
    call .Lwrite_all
    cmp QWORD PTR [rsp], 2
    jne .Lprint_newline

    lea rsi, [rip + .Lspace]
    mov edx, 1
    call .Lwrite_all
    mov rsi, QWORD PTR [rsp + 24]
    mov rdx, QWORD PTR [rsp + 32]
    call .Lwrite_all

.Lprint_newline:
    lea rsi, [rip + .Lnewline]
    mov edx, 1
    call .Lwrite_all
    xor edi, edi
    jmp .Lexit

.Lprint_usage:
    mov edi, 2
    lea rsi, [rip + .Lusage]
    mov edx, .Lusage_end - .Lusage
    call .Lwrite_all
    mov edi, 2

.Lexit:
    mov eax, SYS_exit
    syscall
.size _start, .-_start

.type .Lwrite_all, @function
.Lwrite_all:
    test rdx, rdx
    jz .Lwrite_done

.Lwrite_once:
    mov eax, SYS_write
    syscall
    cmp rax, -EINTR
    je .Lwrite_once
    test rax, rax
    jle .Lwrite_error
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite_once

.Lwrite_done:
    ret

.Lwrite_error:
    mov edi, 3
    jmp .Lexit
.size .Lwrite_all, .-.Lwrite_all

.section .note.GNU-stack,"",@progbits
