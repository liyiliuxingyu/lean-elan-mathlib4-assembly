# SPDX-License-Identifier: Apache-2.0
# Exercise the reusable catalog reader in one process. First path is the
# stage-six tiny module fixture; all subsequent paths must fail.
.intel_syntax noprefix
.include "olean_layout.inc"
.section .rodata
.Lstatm: .asciz "/proc/self/statm"

# These exercise the allocated-but-empty LGZ stream and parse-failed .olean
# ownership paths, both of which require an explicit munmap.
.section .catalog_empty_lgz,"a",@progbits
.ascii "LTR2"
.quad 43
.asciz "x.olean"
.byte 1
.quad 8
.long 0x184d2a50, 0                   # skippable frame, no decoded bytes

.section .catalog_bad_image,"a",@progbits
.ascii "LTR2"
.quad 43
.asciz "x.olean"
.byte 1
.quad 26
.long 0xfd2fb528
.byte 0x20, 17, 137, 0, 0            # single-frame raw 17-byte block
.ascii "LGZ!"
.long 0xabcd0123
.quad 32
.byte 0xd7                           # valid legacy image, unsupported module

.bss
.balign 8
.Lview: .skip VIEW_BYTES
.Lhash: .skip 8
.text
.globl _start
.type _start,@function
_start:
    cmp qword ptr [rsp], 3
    jb .Lfail
    lea r12, [rsp+16]                 # argv[1]
    call .Lresources
    mov r15, rax                      # process virtual pages
    mov rbp, rdx                      # lowest free descriptor
    mov rdi, [r12]
    lea rsi, [rip+.Lview]
    lea rdx, [rip+.Lhash]
    call catalog_open_module
    test eax, eax
    jnz .Lfail
    movabs rax, 0x7d16bec4741f71d8   # independent XXH64 of .ltar_payload
    cmp [rip+.Lhash], rax
    jne .Lfail
    cmp qword ptr [rip+.Lview+VIEW_COUNT], 1
    jne .Lfail
    mov rdi, [rip+.Lview+VIEW_MAPPING]
    mov rsi, [rip+.Lview+VIEW_SIZE]
    mov eax, 11
    syscall
    test rax, rax
    jnz .Lfail
.Lcheck:
    call .Lresources
    cmp r15, rax
    jne .Lfail
    cmp rbp, rdx
    jne .Lfail
    add r12, 8
    mov rdi, [r12]
    test rdi, rdi
    jz .Lsuccess
    # Poison outputs each time to detect partially published views.
    mov rax, -1
    lea rdi, [rip+.Lview]
    mov ecx, VIEW_BYTES/8
    rep stosq
    mov [rip+.Lhash], rax
    mov rdi, [r12]
    lea rsi, [rip+.Lview]
    lea rdx, [rip+.Lhash]
    call catalog_open_module
    cmp eax, -1
    jne .Lfail
    cmp qword ptr [rip+.Lhash], 0
    jne .Lfail
    xor eax, eax
    lea rdi, [rip+.Lview]
    mov ecx, VIEW_BYTES/8
    repe scasq
    jne .Lfail
    jmp .Lcheck
.Lsuccess:
    xor edi, edi
    jmp .Lexit
.Lfail:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall
.size _start,.-_start

# /proc/self/statm's first number is virtual memory in pages, independent
# of RSS. The descriptor allocated for this read detects descriptor leaks.
.Lresources:
    sub rsp, 64
    mov eax, 2                        # open
    lea rdi, [rip+.Lstatm]
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .Lfail
    mov r8, rax
    mov rdi, rax
    mov rsi, rsp
    mov edx, 64
    xor eax, eax                      # read
    syscall
    cmp rax, 2
    jl .Lfail
    lea r10, [rsp+rax]
    mov rdi, r8
    mov eax, 3
    syscall
    mov rsi, rsp
    xor eax, eax
.Ldigit:
    cmp rsi, r10
    jae .Lfail
    movzx edx, byte ptr [rsi]
    inc rsi
    cmp dl, ' '
    je .Lpages
    sub edx, '0'
    cmp edx, 9
    ja .Lfail
    imul rax, 10
    add rax, rdx
    jmp .Ldigit
.Lpages:
    mov rdx, r8
    add rsp, 64
    ret
.section .note.GNU-stack,"",@progbits
