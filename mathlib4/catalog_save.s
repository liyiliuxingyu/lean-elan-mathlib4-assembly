# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "catalog_layout.inc"
.section .rodata
.Lprefix: .ascii ".mathlib-catalog-"
.equ PFXLEN, .-.Lprefix
.Lhex: .ascii "0123456789abcdef"
.text
.globl catalog_save
.hidden catalog_save
.type catalog_save, @function
# (destination, header, four arenas). Stage all bytes in a private sibling;
# ordinary readers see one complete generation across a concurrent rebuild.
catalog_save:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 4280                     # struct stat, random bytes, temp pathname
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov qword ptr [rsp+152], 1        # RENAME_NOREPLACE if no previous index
    mov rdi, r12
    mov esi, 0xa0800                  # O_NOFOLLOW | O_RDONLY | O_NONBLOCK | O_CLOEXEC
    mov eax, 2
    syscall
    cmp rax, -2                       # ENOENT
    je .Lprepare
    test rax, rax
    js .Lerror
    mov ebx, eax
    mov edi, eax
    mov rsi, rsp
    mov eax, 5
    syscall
    test rax, rax
    js .Lreject
    mov eax, [rsp+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Lreject
    mov edi, ebx
    mov edx, H_BYTES
    xor eax, eax
    syscall
    cmp rax, H_BYTES
    jne .Lreject
    mov rax, CAT_MAGIC
    cmp [rsp], rax
    jne .Lreject
    mov edi, ebx
    mov eax, 3
    syscall
    mov qword ptr [rsp+152], 0
.Lprepare:
    lea r15, [rsp+160]
    mov rsi, r12
    mov rdx, rsi
.Lscan:
    mov al, [rsi]
    test al, al
    jz .Lprefix_ready
    inc rsi
    cmp al, '/'
    cmove rdx, rsi
    jmp .Lscan
.Lprefix_ready:
    sub rdx, r12
    cmp rdx, 4096-PFXLEN-17
    ja .Lerror
    mov rdi, r15
    mov rsi, r12
    mov rcx, rdx
    rep movsb
    lea rsi, [rip+.Lprefix]
    mov ecx, PFXLEN
    rep movsb
    mov rbp, rdi
.Lrandom:
    lea rdi, [rsp+144]
    mov esi, 8
    xor edx, edx
    mov eax, 318                      # getrandom
    syscall
    cmp rax, -4
    je .Lrandom
    cmp rax, 8
    jne .Lerror
    mov rax, [rsp+144]
    lea rdx, [rip+.Lhex]
    mov ecx, 16
    mov rdi, rbp
.Lencode:
    mov rsi, rax
    and esi, 15
    mov sil, [rdx+rsi]
    mov [rdi], sil
    inc rdi
    shr rax, 4
    dec ecx
    jnz .Lencode
    mov byte ptr [rdi], 0
    mov rdi, r15
    mov esi, 0x800c1                  # CLOEXEC | EXCL | CREAT | WRONLY
    mov edx, 0x180                    # 0600
    mov eax, 2
    syscall
    cmp rax, -17
    je .Lrandom
    test rax, rax
    js .Lerror
    mov ebx, eax
    mov edi, ebx
    mov rsi, r13
    mov edx, H_BYTES
    call catalog_write
    test eax, eax
    jnz .Ldiscard
    mov ebp, 4
.Lsection:
    mov edi, ebx
    mov rsi, [r14+A_DATA]
    mov rdx, [r14+A_USED]
    call catalog_write
    test eax, eax
    jnz .Ldiscard
    add r14, A_BYTES
    dec ebp
    jnz .Lsection
.Lsync:
    mov edi, ebx
    mov eax, 74                       # fsync before publishing
    syscall
    cmp rax, -4
    je .Lsync
    test rax, rax
    js .Ldiscard
    mov edi, ebx
    mov eax, 3
    syscall
    test rax, rax
    js .Lunlink
    mov edi, -100
    mov rsi, r15
    mov edx, -100
    mov r10, r12
    mov r8, [rsp+152]
    mov eax, 316                      # renameat2
    syscall
    test rax, rax
    js .Lunlink
    jmp .Ldone
.Ldiscard:
    mov edi, ebx
    mov eax, 3
    syscall
.Lunlink:
    mov rdi, r15
    mov eax, 87
    syscall
    jmp .Lerror
.Lreject:
    mov edi, ebx
    mov eax, 3
    syscall
.Lerror:
    mov eax, -1
.Ldone:
    add rsp, 4280
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size catalog_save, .-catalog_save
.section .note.GNU-stack,"",@progbits
