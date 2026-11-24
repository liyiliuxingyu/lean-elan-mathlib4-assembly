/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Installed-toolchain implementations of Elan 4.2.4 which and run. */
.intel_syntax noprefix
.equ CAP, 4096
.text
/* rdi=explicit toolchain or NULL for which, rsi=command argv, rdx=envp,
 * rcx=absolute Elan home, r8=env toolchain. */
.globl elan_command_main
elan_command_main:
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    /* Clap's value_of/values_of requires every selected argument to be UTF-8. */
    push r8
    test rbx, rbx
    jz .Lcheck_argv
    mov rdi, rbx
    call .Lvalid_arg
    test eax, eax
    jz .Lbad_arg
.Lcheck_argv:
    mov rbp, r12
.Lcheck_arg:
    mov rdi, [rbp]
    call .Lvalid_arg
    test eax, eax
    jz .Lbad_arg
    test rbx, rbx
    jz .Largs_valid
    add rbp, 8
    cmp qword ptr [rbp], 0
    jne .Lcheck_arg
.Largs_valid:
    pop rsi
    mov rdi, rbx
    mov rdx, r14
    call elan_select_for_command
    /* Only the manager persists missing default settings and GC roots.
     * Keep the selection result and its full error tuple across this call. */
    push rax
    push rdx
    push rsi
    push rcx
    push r8
    push r9
    mov rdi, r14
    mov rsi, rax
    call elan_command_state
    pop r9
    pop r8
    pop rcx
    pop rsi
    pop rdx
    pop rax
    test rax, rax
    jz .Lselection_error
    mov r15, rax
    mov ecx, edx
    mov r8, r15
    mov rsi, r14
    lea rdi, [rip+.Lprogram]
    lea rdx, [rip+.Lprogram+CAP]
    call elan_toolchain_root
    jc .Llength
    mov rbp, rdi
    /* Toolchain::exists accepts directories and symlinks, including dangling
     * links. A default for "which" does not perform any installation check. */
    test rbx, rbx
    jnz .Lcheck_root
    cmp byte ptr [rip+elan_selection_from_default], 0
    jne .Lbinary
.Lcheck_root:
    lea rdi, [rip+.Lprogram]
    lea rsi, [rip+.Lstat]
    mov eax, 4                     /* stat */
    syscall
    test rax, rax
    js .Lcheck_link
    mov eax, [rsi+24]
    and eax, 0xf000
    cmp eax, 0x4000
    je .Lbinary
.Lcheck_link:
    mov eax, 6                     /* lstat */
    syscall
    test rax, rax
    js .Luninstalled
    mov eax, [rsi+24]
    and eax, 0xf000
    cmp eax, 0xa000
    jne .Luninstalled
.Lbinary:
    mov rdi, rbp
    lea rdx, [rip+.Lprogram+CAP]
    mov rsi, [r12]
    lea r8, [rip+.Lprogram]
    call elan_binary_file
    jc .Llength
    lea rdi, [rip+.Lprogram]
    test rbx, rbx
    jnz .Lrun
    lea rsi, [rip+.Lstat]
    mov eax, 4
    syscall
    test rax, rax
    js .Lnot_file
    mov eax, [rsi+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Lnot_file
    mov rsi, rdi
    mov edi, 1
    call elan_manage_write
    lea rsi, [rip+.Lnewline]
    call elan_manage_write
    xor edi, edi
    mov eax, 60
    syscall
.Lvalid_arg:
    call elan_strlen
    mov rsi, rax
    jmp elan_manage_utf8
.Lbad_arg:
    lea rsi, [rip+.Lbad_arg_text]
    jmp .Lpanic
.Lrun:
    mov rsi, rdi
    mov rdi, r15
    mov rdx, r12
    mov rcx, r13
    jmp elan_manager_launch
.Luninstalled:
    lea rdi, [rip+.Luninstalled_text]
    mov rsi, r15
    lea rdx, [rip+.Linstall_text]
    jmp elan_manage_error
.Llength:
    lea rsi, [rip+.Llength_error]
    jmp .Lerror
.Lselection_error:
    cmp ecx, 1
    je .Lname_error
    cmp ecx, 2
    je .Lpath_error
    cmp ecx, 3
    je .Lno_selection
    /* The selector supplies its other bounded diagnostics to both launchers. */
    mov edi, 2
    mov eax, 1
    syscall
    jmp elan_manage_fail
.Lname_error:
    lea rdi, [rip+.Linvalid]
    mov rsi, r8
    lea rdx, [rip+.Lend_quote]
    jmp elan_manage_error
.Lpath_error:
    /* r8=tried root, r9=joined bin/lean in the selector's scratch space. */
    mov r12, r8
    mov r13, r9
    mov edi, 2
    lea rsi, [rip+.Lno_root]
    call elan_manage_write
    mov rsi, r12
    call elan_manage_write
    lea rdi, [rip+.Lexpected]
    mov rsi, r13
    lea rdx, [rip+.Lto_exist]
    jmp elan_manage_error
.Lno_selection:
    lea rsi, [rip+.Lno_default]
.Lpanic:
    mov edi, 2
    call elan_manage_write
    mov edi, 101                   /* which expects a selected toolchain */
    mov eax, 60
    syscall
.Lnot_file:
    lea rdi, [rip+.Lnot_file_text]
    lea rsi, [rip+.Lprogram]
    lea rdx, [rip+.Lend_quote]
    jmp elan_manage_error
.Lerror:
    mov edi, 2
    call elan_manage_write
    jmp elan_manage_fail
.section .rodata
.Lnot_file_text: .asciz "error: not a file: '"
.Lend_quote: .asciz "'\n"
.Lnewline: .asciz "\n"
.Luninstalled_text: .asciz "error: toolchain '"
.Linstall_text: .asciz "' is not installed; remote installation is unavailable in this build\n"
.Llength_error: .asciz "error: toolchain or binary path exceeds 4095 bytes\n"
.Linvalid: .asciz "error: invalid toolchain name: '"
.Lno_root: .asciz "error: no Lean toolchain found at '"
.Lexpected: .asciz "': expected '"
.Lto_exist: .asciz "' to exist\n"
.Lbad_arg_text: .asciz "error: unexpected invalid UTF-8 code point in command arguments\n"
.Lno_default: .asciz "error: binary not found (no selected toolchain)\n"
.section .bss
.balign 8
.Lstat: .skip 144
.Lprogram: .skip CAP
.section .note.GNU-stack,"",@progbits
