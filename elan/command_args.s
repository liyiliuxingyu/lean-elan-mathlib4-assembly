/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Elan 4.2.4: which <command>, run [--install] <toolchain> <command>... */
.intel_syntax noprefix
.text
/* rdi = argv beginning at subcommand. Return argv at child command in rax,
 * resolved-later toolchain argument or NULL in rdx. Help/errors terminate. */
.globl elan_parse_command_args
elan_parse_command_args:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov rax, [rbx]
    cmp byte ptr [rax], 'r'
    sete bpl
    movzx ebp, bpl                 /* run rather than which */
    xor r12d, r12d                 /* toolchain argument */
    xor r13d, r13d                 /* command argv */
    xor r14d, r14d                 /* bit 0 ends options, bit 1 = --install */
.Lnext:
    add rbx, 8
    mov rdi, [rbx]
    test rdi, rdi
    jz .Ldone
    test r14b, 1
    jnz .Lpositional
    cmp byte ptr [rdi], '-'
    jne .Lpositional
    mov al, [rdi+1]
    test al, al
    jz .Lpositional
    cmp al, '-'
    je .Llong
    cmp al, 'h'
    je .Lhelp
    /* Clap names the first unrecognized short flag. */
    test al, al
    js .Lunexpected
    mov byte ptr [rdi+2], 0
    jmp .Lunexpected
.Llong:
    cmp byte ptr [rdi+2], 0
    jne .Llong_option
    or r14d, 1
    jmp .Lnext
.Llong_option:
    mov rax, rdi
.Loption_end:
    inc rax
    cmp byte ptr [rax], 0
    je .Lmatch_option
    cmp byte ptr [rax], '='
    jne .Loption_end
    mov byte ptr [rax], 0           /* flags take no value, even with =value */
.Lmatch_option:
    lea rsi, [rip+.Lhelp_opt]
    call .Lequal
    je .Lhelp
    test ebp, ebp
    jz .Lunexpected
    mov rdi, [rbx]
    lea rsi, [rip+.Linstall]
    call .Lequal
    jne .Lunexpected
    test r14b, 2
    jnz .Lduplicate
    or r14d, 2
    jmp .Lnext
.Lpositional:
    test ebp, ebp
    jz .Lcommand
    test r12, r12
    jnz .Lcommand
    mov r12, rdi
    jmp .Lnext
.Lcommand:
    test r13, r13
    jnz .Lunexpected
    mov r13, rbx
    test ebp, ebp
    jz .Lnext
    /* TrailingVarArg makes every later token a child argument. */
.Ldone:
    test r13, r13
    jz .Lmissing
    mov rax, r13
    mov rdx, r12
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.Lequal:
    lodsb
    cmp al, [rdi]
    jne .Lend
    inc rdi
    test al, al
    jnz .Lequal
.Lend:
    ret
.Lhelp:
    lea rsi, [rip+.Lwhich_help]
    lea rax, [rip+.Lrun_help]
    test ebp, ebp
    cmovnz rsi, rax
    mov edi, 1
    call elan_manage_write
    xor edi, edi
    mov eax, 60
    syscall
.Lmissing:
    mov edi, 2
    lea rsi, [rip+.Lrequired]
    call elan_manage_write
    test ebp, ebp
    jz .Lwhich_required
    test r12, r12
    jnz .Lrun_required
    lea rsi, [rip+.Ltoolchain_required]
    call elan_manage_write
.Lrun_required:
    lea rsi, [rip+.Lcommands_required]
    jmp .Lusage
.Lwhich_required:
    lea rsi, [rip+.Lcommand_required]
    jmp .Lusage
.Lunexpected:
    mov edi, 2
    lea rsi, [rip+.Lfound]
    call elan_manage_write
    mov rsi, [rbx]
    call elan_manage_write
    lea rsi, [rip+.Lnot_expected]
.Lusage:
    call elan_manage_write
    lea rsi, [rip+.Lwhich_usage]
    lea rax, [rip+.Lrun_usage]
    test ebp, ebp
    cmovnz rsi, rax
    call elan_manage_write
    jmp elan_manage_fail
.Lduplicate:
    mov edi, 2
    lea rsi, [rip+.Lduplicated]
    call elan_manage_write
    jmp elan_manage_fail
.section .rodata
.Lhelp_opt: .asciz "--help"
.Linstall: .asciz "--install"
.Lfound: .asciz "error: Found argument '"
.Lnot_expected: .asciz "' which wasn't expected, or isn't valid in this context\n"
.Lrequired: .asciz "error: The following required arguments were not provided:\n"
.Ltoolchain_required: .asciz "    <toolchain>\n"
.Lcommands_required: .asciz "    <command>...\n"
.Lcommand_required: .asciz "    <command>\n"
.Lwhich_usage: .asciz "\nUSAGE:\n    elan which <command>\n\nFor more information try --help\n"
.Lrun_usage: .asciz "\nUSAGE:\n    elan run [FLAGS] <toolchain> <command>...\n\nFor more information try --help\n"
.Lduplicated: .asciz "error: The argument '--install' was provided more than once, but cannot be used multiple times\n\nUSAGE:\n    elan run <toolchain> <command>... --install\n\nFor more information try --help\n"
.Lwhich_help:
    .ascii "elan-which \n"
    .ascii "Display which binary will be run for a given command\n"
    .ascii "\n"
    .ascii "USAGE:\n"
    .ascii "    elan which <command>\n"
    .ascii "\n"
    .ascii "FLAGS:\n"
    .ascii "    -h, --help    Prints help information\n"
    .ascii "\n"
    .ascii "ARGS:\n"
    .ascii "    <command>    \n"
    .byte 0
.Lrun_help:
    .ascii "elan-run \n"
    .ascii "Run a command with an environment configured for a given toolchain\n"
    .ascii "\n"
    .ascii "USAGE:\n"
    .ascii "    elan run [FLAGS] <toolchain> <command>...\n"
    .ascii "\n"
    .ascii "FLAGS:\n"
    .ascii "    -h, --help       Prints help information\n"
    .ascii "        --install    Install the requested toolchain if needed\n"
    .ascii "\n"
    .ascii "ARGS:\n"
    .ascii "    <toolchain>     Toolchain name, such as 'stable', 'beta', 'nightly', or '4.3.0'. For more information see `elan\n"
    .ascii "                    help toolchain`\n"
    .ascii "    <command>...    \n"
    .ascii "\n"
    .ascii "DISCUSSION:\n"
    .ascii "    Configures an environment to use the given toolchain and then runs\n"
    .ascii "    the specified program. The command may be any program, not just\n"
    .ascii "    lean or lake. This can be used for testing arbitrary toolchains\n"
    .ascii "    without setting an override.\n"
    .ascii "\n"
    .ascii "    Commands explicitly proxied by `elan` (such as `lean` and\n"
    .ascii "    `lake`) also have a shorthand for this available. The toolchain\n"
    .ascii "    can be set by using `+toolchain` as the first argument. These are\n"
    .ascii "    equivalent:\n"
    .ascii "\n"
    .ascii "        $ lake +nightly build\n"
    .ascii "\n"
    .ascii "        $ elan run --install nightly lake build\n"
    .byte 0
.section .note.GNU-stack,"",@progbits
