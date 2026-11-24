/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Standalone Linux test child for elan-asm-run. */
.intel_syntax noprefix

.equ SYS_WRITE, 1
.equ SYS_EXIT, 60
.equ ERR_EINTR, -4
.equ PROBE_STATUS, 37

.section .text
.globl _start
.type _start, @function
_start:
    mov     rbx, [rsp]
    lea     r12, [rsp+8]
    lea     r13, [r12+rbx*8+8]
    xor     ebp, ebp
.Largument:
    cmp     rbp, rbx
    jae     .Lenvironment
    mov     rsi, [r12+rbp*8]
    call    .Lline
    inc     rbp
    jmp     .Largument

.Lenvironment:
    lea     r14, [rip+.Lkeys]
    lea     r15, [rip+.Lkeys_end]
.Lkey:
    cmp     r14, r15
    jae     .Lsuccess
    mov     rbp, r13
.Lfind:
    mov     rdi, [rbp]
    test    rdi, rdi
    jz      .Lnext_key
    mov     rsi, [r14]
    mov     rcx, [r14+8]
    repe    cmpsb
    je      .Lfound
    add     rbp, 8
    jmp     .Lfind
.Lfound:
    mov     rsi, [rbp]
    call    .Lline
.Lnext_key:
    add     r14, 16
    jmp     .Lkey

.Lsuccess:
    mov     edi, PROBE_STATUS
    jmp     .Lexit
.Lwrite_error:
    mov     edi, 1
.Lexit:
    mov     eax, SYS_EXIT
    syscall
.size _start, .-_start

.Lline:
    xor     edx, edx
.Llength:
    cmp     byte ptr [rsi+rdx], 0
    je      .Lline_ready
    inc     rdx
    jmp     .Llength
.Lline_ready:
    test    rdx, rdx
    jz      .Lline_newline
    call    .Lwrite
.Lline_newline:
    lea     rsi, [rip+.Lnewline]
    mov     edx, 1
.Lwrite:
    mov     edi, 1
.Lwrite_more:
    mov     eax, SYS_WRITE
    syscall
    cmp     rax, ERR_EINTR
    je      .Lwrite_more
    test    rax, rax
    jle     .Lwrite_error
    add     rsi, rax
    sub     rdx, rax
    jnz     .Lwrite_more
    ret

.section .rodata
.Lnewline: .byte 10
.Lkey_keep: .ascii "KEEP="
.Lkey_home: .ascii "ELAN_HOME="
.Lkey_toolchain: .ascii "ELAN_TOOLCHAIN="
.Lkey_count: .ascii "LEAN_RECURSION_COUNT="
.Lkey_path: .ascii "PATH="
.balign 8
.Lkeys:
    .quad .Lkey_keep, .Lkey_home-.Lkey_keep
    .quad .Lkey_home, .Lkey_toolchain-.Lkey_home
    .quad .Lkey_toolchain, .Lkey_count-.Lkey_toolchain
    .quad .Lkey_count, .Lkey_path-.Lkey_count
    .quad .Lkey_path, 5
.Lkeys_end:

.section .note.GNU-stack,"",@progbits
