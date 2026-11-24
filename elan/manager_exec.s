/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Toolchain::create_command and Unix execvp search for "elan run". */
.intel_syntax noprefix
.equ CAP, 4096
.text
/* rdi=candidate binary, rsi=argv, rdx=envp, rcx=selected name,
 * r8=effective child PATH or NULL, r9=parent recursion count. Never returns. */
.globl elan_manager_exec
elan_manager_exec:
    mov r12, rsi
    mov r13, rdx
    mov r14, [rsi]                  /* original spelling for fallback and errors */
    mov r15, r8
    mov rbx, rdi
    mov rbp, rcx
    lea rsi, [rip+.Lstat]
    mov eax, 4
    syscall
    test rax, rax
    js .Lfallback
    mov eax, [rsi+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Lfallback
    mov [r12], rbx                  /* upstream sets argv[0] to toolchain path */
    mov rdi, rbx
    jmp .Ldirect
.Lfallback:
    cmp r9d, 4
    ja .Lrecursion
    cmp byte ptr [r14], 0
    je .Lnot_found
    mov rsi, r14
.Lslash:
    lodsb
    cmp al, '/'
    je .Loriginal
    test al, al
    jnz .Lslash
    test r15, r15
    jnz .Lpath_entry
    lea r15, [rip+.Ldefault_path]
.Lpath_entry:
    mov rsi, r15
.Lpath_end:
    lodsb
    cmp al, ':'
    je .Ltry
    test al, al
    jnz .Lpath_end
.Ltry:
    mov rbx, rsi
    mov rcx, rsi
    sub rcx, r15
    dec rcx
    cmp rcx, CAP-2
    ja .Ladvance
    lea rdi, [rip+.Lcandidate]
    mov rsi, r15
    test rcx, rcx
    jz .Lappend
    rep movsb
    mov byte ptr [rdi], '/'
    inc rdi
.Lappend:
    lea rdx, [rip+.Lcandidate+CAP]
    mov rsi, r14
    call elan_append_z
    jc .Ladvance
    lea rdi, [rip+.Lcandidate]
    call .Lexec
    cmp eax, -13                    /* remember EACCES if no later entry works */
    jne .Lsearch_error
    mov byte ptr [rip+.Ldenied], 1
    jmp .Ladvance
.Lsearch_error:
    cmp eax, -2
    je .Ladvance
    cmp eax, -20
    jne .Lexec_error
.Ladvance:
    cmp byte ptr [rbx-1], 0
    je .Lsearch_done
    mov r15, rbx
    jmp .Lpath_entry
.Lsearch_done:
    cmp byte ptr [rip+.Ldenied], 0
    je .Lnot_found
    mov eax, -13
    jmp .Lexec_error
.Lnot_found:
    mov eax, -2
    jmp .Lexec_error
.Loriginal:
    mov rdi, r14
.Ldirect:
    call .Lexec
.Lexec_error:
    mov edx, eax
    lea rdi, [rip+.Lcommand_failed]
    mov rsi, r14
    jmp elan_manage_io_error
.Lexec:
    mov rsi, r12
    mov rdx, r13
    mov eax, 59                     /* execve */
    syscall
    ret
.Lrecursion:
    mov edi, 2
    lea rsi, [rip+.Ltoolchain]
    call elan_manage_write
    mov rsi, rbp
    call elan_manage_write
    lea rdi, [rip+.Lmissing]
    mov rsi, rbx
    lea rdx, [rip+.Lend]
    jmp elan_manage_error
.section .rodata
.Lcommand_failed: .asciz "error: command failed: '"
.Ltoolchain: .asciz "error: toolchain '"
.Lmissing: .asciz "' does not have the binary `"
.Lend: .asciz "`\n"
.Ldefault_path: .asciz "/usr/local/bin:/bin:/usr/bin"
.section .bss
.balign 8
.Lstat: .skip 144
.Lcandidate: .skip CAP
.Ldenied: .skip 1
.section .note.GNU-stack,"",@progbits
