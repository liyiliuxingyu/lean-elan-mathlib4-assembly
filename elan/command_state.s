/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Side effects of SettingsFile::read_settings and gc::add_root in which. */
.intel_syntax noprefix
.equ CAP, 4096
.text
/* rdi = Elan home, rsi = valid selected descriptor or NULL. */
.globl elan_command_state
elan_command_state:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov rbp, rsi
    cmp byte ptr [rip+elan_selection_missing_settings], 0
    je .Lproject
    lea r8, [rip+.Lsettings_file]
    call .Lpath
    jc .Ltoo_long
    mov esi, 0x800c1               /* O_CLOEXEC | O_CREAT | O_EXCL | O_WRONLY */
    mov edx, 0666
    mov eax, 2
    syscall
    cmp eax, -17
    je .Lproject
    test rax, rax
    js .Lsettings_error
    mov rdi, rax
    lea rsi, [rip+.Ldefaults]
    mov edx, OFFSET FLAT:.Ldefaults_len
    call .Lwrite
    test eax, eax
    js .Lsettings_error
    mov eax, 3
    syscall
.Lproject:
    test rbp, rbp
    jz .Ldone
    mov rbp, [rip+elan_selection_project_root]
    test rbp, rbp
    jz .Ldone
    lea r8, [rip+.Lknown]
    call .Lpath
    jc .Ltoo_long
    xor ebx, ebx                    /* nonzero when the registry existed */
    mov esi, 0x80cc2               /* O_CLOEXEC|O_NONBLOCK|O_APPEND|CREAT|EXCL|RDWR */
    mov edx, 0666
    mov eax, 2
    syscall
    test rax, rax
    jns .Llock
    cmp eax, -17
    jne .Lmaybe_read
    inc ebx
    mov esi, 0x80c02               /* O_CLOEXEC | O_NONBLOCK | O_APPEND | O_RDWR */
    mov eax, 2
    syscall
    test rax, rax
    jns .Llock
.Lmaybe_read:
    mov esi, 0x80800               /* Ignore registry write errors when readable. */
    mov eax, 2
    syscall
    test rax, rax
    jns .Llock
    cmp eax, -2
    je .Ldone
    jmp .Lregistry_error
.Llock:
    mov r13, rax
.Lretry_lock:
    mov rdi, r13
    mov esi, 2                     /* LOCK_EX; concurrent manager adds deduplicate */
    mov eax, 73
    syscall
    cmp eax, -4
    je .Lretry_lock
    test rax, rax
    js .Lregistry_error
    lea rsi, [rip+.Lstat]
    mov eax, 5
    syscall
    test rax, rax
    js .Lregistry_error
    mov eax, [rsi+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Linvalid_registry
    mov r14, [rsi+48]
    test r14, r14
    jz .Ladd
    mov ebx, 1
    xor edi, edi
    mov rsi, r14
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    cmp rax, -4095
    jae .Lregistry_error
    mov r15, rax
    xor r12d, r12d
.Lread:
    mov rdi, r13
    lea rsi, [r15+r12]
    mov rdx, r14
    sub rdx, r12
    jz .Lvalidate
    xor eax, eax
    syscall
    cmp eax, -4
    je .Lread
    test rax, rax
    js .Lregistry_error
    jz .Lvalidate
    add r12, rax
    jmp .Lread
.Lvalidate:
    mov rdi, r15
    mov rsi, r12
    call elan_manage_utf8
    test eax, eax
    jz .Linvalid_registry
    mov rdi, rbp
    call elan_strlen
    mov r8, rax
    mov r9, r15
    lea r10, [r15+r12]
.Lline:
    mov rax, r9
.Lscan:
    cmp rax, r10
    jae .Lcompare
    cmp byte ptr [rax], 10
    je .Lcompare
    inc rax
    jmp .Lscan
.Lcompare:
    mov rcx, rax
    sub rcx, r9
    cmp rcx, r8
    jne .Lnext
    mov rdi, rbp
    mov rsi, r9
    repe cmpsb
    je .Lclose
.Lnext:
    cmp rax, r10
    jae .Ladd
    lea r9, [rax+1]
    jmp .Lline
.Ladd:
    /* Path limit leaves space for both prefix separator and trailing NUL. */
    mov rsi, rbp
    lea rdi, [rip+.Lentry+1]
    lea rdx, [rip+.Lentry+CAP+1]
    call elan_append_z
    jc .Ltoo_long
    mov rdx, rdi
    lea rsi, [rip+.Lentry+1]
    test ebx, ebx
    jz .Lwrite_entry
    dec rsi
    mov byte ptr [rsi], 10
.Lwrite_entry:
    sub rdx, rsi
    mov rdi, r13
    call .Lwrite
.Lclose:
    /* This single-shot process exits after which. munmap the registry anyway
     * so this helper also keeps its allocation bounded across repeated uses. */
    test r14, r14
    jz .Lclose_fd
    mov rdi, r15
    mov rsi, r14
    mov eax, 11
    syscall
.Lclose_fd:
    mov rdi, r13
    mov eax, 3
    syscall
.Ldone:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.Lwrite:
    test rdx, rdx
    jz .Lwritten
    mov eax, 1
    syscall
    cmp eax, -4
    je .Lwrite
    test rax, rax
    jle .Lwrite_done
    add rsi, rax
    sub rdx, rax
    jmp .Lwrite
.Lwritten:
    xor eax, eax
.Lwrite_done:
    ret
.Lpath:
    lea rdi, [rip+.Lpathname]
    lea rdx, [rip+.Lpathname+CAP]
    mov rsi, r12
    call elan_append_z
    jc .Lpath_done
    mov rsi, r8
    call elan_join_component
    lea rdi, [rip+.Lpathname]
.Lpath_done:
    ret
.Lsettings_error:
    lea rdi, [rip+.Lwrite_settings]
    jmp .Lerror
.Lregistry_error:
    lea rdi, [rip+.Lread_registry]
.Lerror:
    mov edx, eax
    lea rsi, [rip+.Lpathname]
    jmp elan_manage_io_error
.Linvalid_registry:
    mov edi, 2
    lea rsi, [rip+.Linvalid]
    call elan_manage_write
    jmp elan_manage_fail
.Ltoo_long:
    mov edi, 2
    lea rsi, [rip+.Llength]
    call elan_manage_write
    jmp elan_manage_fail
.section .rodata
.Lsettings_file: .asciz "settings.toml"
.Lknown: .asciz "known-projects"
.Ldefaults: .ascii "telemetry = false\nversion = \"12\"\n\n[overrides]\n"
.equ .Ldefaults_len, .-.Ldefaults
.Lwrite_settings: .asciz "error: could not write settings file: '"
.Lread_registry: .asciz "error: could not read known-projects file: '"
.Linvalid: .asciz "error: known-projects must be a regular UTF-8 file\n"
.Llength: .asciz "error: project or settings path exceeds 4095 bytes\n"
.section .bss
.balign 8
.Lstat: .skip 144
.Lpathname: .skip CAP
.Lentry: .skip CAP+1
.section .note.GNU-stack,"",@progbits
