/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/*
 * Local launch for an already resolved Elan v4.2.4 toolchain.
 * Linux x86-64, GNU as Intel syntax, process entry point at _start.
 */
.intel_syntax noprefix

.equ SYS_WRITE, 1
.equ SYS_MMAP, 9
.equ SYS_EXECVE, 59
.equ SYS_EXIT, 60
.equ ERR_EINTR, -4
.equ ERR_ENOENT, -2
.equ ERR_ENOTDIR, -20
.equ PATH_CAPACITY, 4096
.equ ENV_PATH_CAPACITY, 131072
.equ ENV_HOME, 0
.equ ENV_ELAN_HOME, 1
.equ ENV_PATH, 2
.equ ENV_RECURSION, 3
.equ ENV_TOOLCHAIN, 4
.equ ENV_NO_NOTICE, 5
.equ ENV_SLOTS, 6

.section .text
.ifdef MANAGER_LAUNCH
/* Resolved manager command. rdi descriptor, rsi binary_file, rdx child argv,
 * rcx envp. Manager already checked toolchain existence. */
.globl elan_manager_launch
elan_manager_launch:
    mov r12, rdi
    mov [rip+.Lselected_name], rdi
    mov [rip+.Lselected_file], rsi
    mov r13, rdx
    mov r14, rcx
    jmp .Lcollect_environment
.else
.globl _start
.type _start, @function
_start:
    mov     rax, [rsp]
    lea     r13, [rsp+8]             /* argv */
    lea     r14, [r13+rax*8+8]      /* envp */
.ifdef AUTO_SELECT
    cmp     rax, 2
    jb      .Lusage
    add     r13, 8                   /* slot for child argv[0] */
    mov     r15, [r13]               /* actual command basename */
    xor     r12d, r12d               /* optional +toolchain */
    mov     rsi, [r13+8]
    test    rsi, rsi
    jz      .Lproxy_environment
    cmp     byte ptr [rsi], '+'
    jne     .Lproxy_environment
    lea     r12, [rsi+1]
    add     r13, 8                   /* consume only the first child argument */
.Lproxy_environment:
    and     rsp, -16
    jmp     .Lcollect_environment
.else
    cmp     rax, 3
    jb      .Lusage
    mov     r12, [r13+8]             /* resolved descriptor */
    add     r13, 16                  /* slot for child argv[0] */
    mov     r15, [r13]               /* executable basename */
    and     rsp, -16

    mov     rdi, r12
    call    elan_strlen
    mov     rsi, rax
    lea     rdx, [rip+.Ldesc]
    call    elan_parse_resolved
    test    eax, eax
    jz      .Linvalid_toolchain
    cmp     eax, 1
    jne     .Lvalidate_command
    cmp     byte ptr [r12], '.'
    jne     .Lvalidate_command
    cmp     byte ptr [r12+1], 0
    je      .Linvalid_toolchain
    cmp     word ptr [r12+1], '.'
    je      .Linvalid_toolchain

.endif
.Lvalidate_command:
    cmp     byte ptr [r15], 0
    je      .Linvalid_command
    cmp     byte ptr [r15], '.'
    jne     .Lscan_command
    cmp     byte ptr [r15+1], 0
    je      .Linvalid_command
    cmp     word ptr [r15+1], '.'
    je      .Linvalid_command
.Lscan_command:
    xor     ecx, ecx
.Lscan_command_byte:
    mov     al, [r15+rcx]
    test    al, al
.ifdef AUTO_SELECT
    jz      .Lbuild_program
.else
    jz      .Lcollect_environment
.endif
    cmp     al, '/'
    je      .Linvalid_command
    inc     rcx
    jmp     .Lscan_command_byte

.endif /* standalone launch entry */
.Lcollect_environment:
    mov     rbp, r14
.Lread_env:
    mov     rdi, [rbp]
    test    rdi, rdi
    jz      .Lparse_recursion
    call    .Lenvironment_entry
    cmp     eax, ENV_SLOTS
    jae     .Lnext_env
    lea     rcx, [rip+.Lenv_values]
    mov     [rcx+rax*8], rdx
.Lnext_env:
    add     rbp, 8
    jmp     .Lread_env

.Lparse_recursion:
    mov     rsi, [rip+.Lenv_values+ENV_RECURSION*8]
    call    elan_read_u32
    cmp     eax, 5
    ja      .Lrecursion_limit
    mov     [rip+.Lparent_count], eax
    /* env_var::inc parses a signed i32, whereas the recursion guard and
     * toolchain fallback parse u32. Preserve negative counter values. */
    mov     rsi, [rip+.Lenv_values+ENV_RECURSION*8]
    test    rsi, rsi
    jz      .Linc_count
    cmp     byte ptr [rsi], '-'
    jne     .Linc_count
    inc     rsi
    cmp     byte ptr [rsi], '+'
    je      .Linc_count
    call    elan_read_u32
    cmp     eax, 0x80000000
    jbe     .Lnegative
    xor     eax, eax
.Lnegative:
    neg     eax
.Linc_count:
    inc     eax
    mov     esi, eax
    test    eax, eax
    jns     .Ldigits
    neg     eax
.Ldigits:
    lea     rdi, [rip+.Lrecursion_end]
    mov     byte ptr [rdi], 0
    mov     ecx, 10
.Ldigit:
    xor     edx, edx
    div     ecx
    add     dl, '0'
    dec     rdi
    mov     [rdi], dl
    test    eax, eax
    jne     .Ldigit
    test    esi, esi
    jns     .Lcopy_count
    dec     rdi
    mov     byte ptr [rdi], '-'
.Lcopy_count:
    mov     rsi, rdi
    lea     rdi, [rip+.Lrecursion_digit]
    lea     rdx, [rip+.Lrecursion_end+1]
    call    elan_append_z

    mov     rdi, [rip+.Lenv_values+ENV_ELAN_HOME*8]
    mov     rsi, [rip+.Lenv_values+ENV_HOME*8]
    lea     rdx, [rip+.Lhome]
    call    elan_home_path
    cmp     eax, 1
    je      .Lmissing_home
    cmp     eax, 2
    je      .Lbad_cwd
    test    eax, eax
    jnz     .Ltoo_long

.Lhome_ready:
.ifdef MANAGER_LAUNCH
    jmp .Lbuild_home_env
.else
.ifdef AUTO_SELECT
    mov     rdi, r12
    mov     rsi, [rip+.Lenv_values+ENV_TOOLCHAIN*8]
    lea     rdx, [rip+.Lhome]
    mov     rcx, [rip+.Lenv_values+ENV_NO_NOTICE*8]
    call    elan_select_installed
    test    rax, rax
    jz      .Lreport_usage           /* rsi, rdx carry selection diagnostic */
    mov     r12, rax
    mov     [rip+.Ldesc], edx
    jmp     .Lvalidate_command
.endif
.Lbuild_program:
    lea     rdi, [rip+.Lprogram]
    lea     rdx, [rip+.Lprogram+PATH_CAPACITY]
    mov     ecx, [rip+.Ldesc]
    mov     r8, r12
    lea     rsi, [rip+.Lhome]
    call    elan_toolchain_root
    jc      .Ltoo_long
    mov     rsi, r15
    lea     r8, [rip+.Lprogram]
    call    elan_binary_file
    jc      .Ltoo_long
.endif

.Lbuild_home_env:
    lea     rdi, [rip+.Lhome_env]
    lea     rdx, [rip+.Lhome_env+PATH_CAPACITY+10]
    lea     rsi, [rip+.Lkey_elan_home]
    call    elan_append_z
    lea     rsi, [rip+.Lhome]
    call    elan_append_z
    jc      .Ltoo_long

    lea     rdi, [rip+.Ltoolchain_env]
    lea     rdx, [rip+.Ltoolchain_env+PATH_CAPACITY+15]
    lea     rsi, [rip+.Lkey_toolchain]
    call    elan_append_z
    mov     rsi, r12
    call    elan_append_z
    jc      .Ltoo_long

    /* Rust's join_paths rejects a search entry containing a colon. */
    lea     rsi, [rip+.Lhome]
.Lcheck_path_entry:
    lodsb
    cmp     al, ':'
    je      .Lbuild_env_vector
    test    al, al
    jnz     .Lcheck_path_entry
    lea     rdi, [rip+.Lpath_env]
    lea     rdx, [rip+.Lpath_env+ENV_PATH_CAPACITY]
    lea     rsi, [rip+.Lkey_path]
    call    elan_append_z
    lea     rsi, [rip+.Lhome]
    call    elan_append_z
    jc      .Ltoo_long
    lea     rsi, [rip+.Lbin]
    call    elan_join_component
    jc      .Ltoo_long
    mov     rsi, [rip+.Lenv_values+ENV_PATH*8]
    test    rsi, rsi
    jz      .Lbuild_env_vector
    mov     byte ptr [rdi], ':'
    inc     rdi
    call    elan_append_z
    jc      .Ltoo_long

.Lbuild_env_vector:
    mov     rsi, rbp
    sub     rsi, r14
    add     rsi, 5*8               /* four replacements and final NULL */
    xor     edi, edi
    mov     edx, 3                 /* PROT_READ|PROT_WRITE */
    mov     r10d, 0x22             /* MAP_PRIVATE|MAP_ANONYMOUS */
    mov     r8, -1
    xor     r9d, r9d
    mov     eax, SYS_MMAP
    syscall
    cmp     rax, -4095
    jae     .Lno_memory
    mov     r12, rax
    mov     rbx, rax
.Lcopy_env:
    mov     rdi, [r14]
    test    rdi, rdi
    jz      .Lfinish_env
    call    .Lenvironment_entry
    cmp     eax, ENV_PATH
    jne     .Lcopy_or_skip
    cmp     byte ptr [rip+.Lpath_env], 0
    je      .Lkeep_env
.Lcopy_or_skip:
    cmp     eax, ENV_ELAN_HOME
    jb      .Lkeep_env
    cmp     eax, ENV_TOOLCHAIN+1
    jb      .Ladvance_env
.Lkeep_env:
    mov     rax, [r14]
    mov     [rbx], rax
    add     rbx, 8
.Ladvance_env:
    add     r14, 8
    jmp     .Lcopy_env
.Lfinish_env:
    lea     rax, [rip+.Lhome_env]
    mov     [rbx], rax
    lea     rax, [rip+.Ltoolchain_env]
    mov     [rbx+8], rax
    lea     rax, [rip+.Lrecursion_env]
    mov     [rbx+16], rax
    add     rbx, 24
    cmp     byte ptr [rip+.Lpath_env], 0
    je      .Lterminate_env
    lea     rax, [rip+.Lpath_env]
    mov     [rbx], rax
    add     rbx, 8
.Lterminate_env:
    mov     qword ptr [rbx], 0

.ifdef MANAGER_LAUNCH
    mov     rdi, [rip+.Lselected_file]
    mov     rsi, r13
    mov     rdx, r12
    mov     rcx, [rip+.Lselected_name]
    mov     r8, [rip+.Lenv_values+ENV_PATH*8]
    cmp     byte ptr [rip+.Lpath_env], 0
    je      .Lmanager_exec
    lea     r8, [rip+.Lpath_env+5]
.Lmanager_exec:
    mov     r9d, [rip+.Lparent_count]
    jmp     elan_manager_exec
.else
    lea     rdi, [rip+.Lprogram]
    mov     rsi, r13                /* replace command/selector slot with argv[0] */
    mov     [rsi], rdi
    mov     rdx, r12
    mov     eax, SYS_EXECVE
    syscall
    cmp     rax, ERR_ENOENT
    je      .Lprogram_missing
    cmp     rax, ERR_ENOTDIR
    je      .Lprogram_missing
    lea     rsi, [rip+.Lexec_error]
    mov     edx, OFFSET FLAT:.Lexec_error_len
    mov     r10d, 126
    jmp     .Lreport

.endif
.Lusage:
    lea     rsi, [rip+.Lusage_error]
    mov     edx, OFFSET FLAT:.Lusage_error_len
    jmp     .Lreport_usage
.Linvalid_toolchain:
    lea     rsi, [rip+.Ldescriptor_error]
    mov     edx, OFFSET FLAT:.Ldescriptor_error_len
    jmp     .Lreport_usage
.Linvalid_command:
    lea     rsi, [rip+.Lcommand_error]
    mov     edx, OFFSET FLAT:.Lcommand_error_len
    jmp     .Lreport_usage
.Lmissing_home:
    lea     rsi, [rip+.Lhome_error]
    mov     edx, OFFSET FLAT:.Lhome_error_len
    jmp     .Lreport_usage
.Lbad_cwd:
    lea     rsi, [rip+.Lcwd_error]
    mov     edx, OFFSET FLAT:.Lcwd_error_len
    jmp     .Lreport_usage
.Lrecursion_limit:
    lea     rsi, [rip+.Lrecursion_error]
    mov     edx, OFFSET FLAT:.Lrecursion_error_len
    jmp     .Lreport_usage
.Ltoo_long:
    lea     rsi, [rip+.Llength_error]
    mov     edx, OFFSET FLAT:.Llength_error_len
.Lreport_usage:
    mov     r10d, 2
    jmp     .Lreport
.Lno_memory:
    lea     rsi, [rip+.Lmemory_error]
    mov     edx, OFFSET FLAT:.Lmemory_error_len
    mov     r10d, 126
    jmp     .Lreport
.Lprogram_missing:
    lea     rsi, [rip+.Lmissing_error]
    mov     edx, OFFSET FLAT:.Lmissing_error_len
    mov     r10d, 127
.Lreport:
    mov     edi, 2
.Lwrite_diagnostic:
    mov     eax, SYS_WRITE
    syscall
    cmp     rax, ERR_EINTR
    je      .Lwrite_diagnostic
    test    rax, rax
    jle     .Lexit
    add     rsi, rax
    sub     rdx, rax
    jnz     .Lwrite_diagnostic
.Lexit:
    mov     edi, r10d
    mov     eax, SYS_EXIT
    syscall
.ifndef MANAGER_LAUNCH
.size _start, .-_start
.endif

/* rdi = environment string; eax = key number or -1; rdx = value. */
.Lenvironment_entry:
    mov     r8, rdi
    lea     r10, [rip+.Lkeys]
    xor     eax, eax
.Lenvironment_compare:
    mov     rdi, r8
    mov     rsi, [r10]
    mov     rcx, [r10+8]
    repe    cmpsb
    je      .Lenvironment_found
    inc     eax
    add     r10, 16
    cmp     eax, ENV_SLOTS
    jb      .Lenvironment_compare
    mov     eax, -1
    ret
.Lenvironment_found:
    mov     rdx, rdi
    ret

.section .rodata
.Ltoolchains: .asciz "toolchains"
.Lbin:        .asciz "bin"

.macro ASCIZ label, string
\label:
    .asciz "\string"
.equ \label\()_len, .-\label-1
.endm
ASCIZ .Lkey_home, "HOME="
ASCIZ .Lkey_elan_home, "ELAN_HOME="
ASCIZ .Lkey_path, "PATH="
ASCIZ .Lkey_recursion, "LEAN_RECURSION_COUNT="
ASCIZ .Lkey_toolchain, "ELAN_TOOLCHAIN="
ASCIZ .Lkey_no_notice, "ELAN_NO_OVERRIDE_NOTICE="

.balign 8
.Lkeys:
.quad .Lkey_home, .Lkey_home_len
.quad .Lkey_elan_home, .Lkey_elan_home_len
.quad .Lkey_path, .Lkey_path_len
.quad .Lkey_recursion, .Lkey_recursion_len
.quad .Lkey_toolchain, .Lkey_toolchain_len
.quad .Lkey_no_notice, .Lkey_no_notice_len

.ifdef AUTO_SELECT
ASCIZ .Lusage_error, "usage: elan-asm-proxy COMMAND [+TOOLCHAIN] [ARG ...]\n"
.else
ASCIZ .Lusage_error, "usage: elan-asm-run TOOLCHAIN COMMAND [ARG ...]\n"
.endif
.macro LAUNCH_ERROR label, value
.ifdef AUTO_SELECT
ASCIZ \label, "elan-asm-proxy: \value\n"
.else
ASCIZ \label, "elan-asm-run: \value\n"
.endif
.endm
LAUNCH_ERROR .Ldescriptor_error, "expected a resolved toolchain descriptor"
LAUNCH_ERROR .Lcommand_error, "expected an executable basename inside bin"
LAUNCH_ERROR .Lhome_error, "set ELAN_HOME or HOME"
LAUNCH_ERROR .Lcwd_error, "cannot resolve a relative home directory"
LAUNCH_ERROR .Lrecursion_error, "toolchain launcher recursion limit exceeded"
LAUNCH_ERROR .Llength_error, "path or child environment entry is too long"
LAUNCH_ERROR .Lmemory_error, "cannot allocate the child environment"
LAUNCH_ERROR .Lmissing_error, "installed toolchain executable not found"
LAUNCH_ERROR .Lexec_error, "cannot execute the selected toolchain binary"

.section .data
.Lrecursion_env:
    .ascii "LEAN_RECURSION_COUNT="
.Lrecursion_digit:
    .skip 11
.Lrecursion_end: .byte 0

.section .bss
.balign 8
.Lparent_count:  .skip 8
.Ldesc:          .skip 40
.Lenv_values:    .skip ENV_SLOTS*8
.Lhome:          .skip PATH_CAPACITY
.Lprogram:       .skip PATH_CAPACITY
.Lhome_env:      .skip PATH_CAPACITY+10
.Ltoolchain_env: .skip PATH_CAPACITY+15
.Lpath_env:      .skip ENV_PATH_CAPACITY
.ifdef MANAGER_LAUNCH
.balign 8
.Lselected_name: .skip 8
.Lselected_file: .skip 8
.endif

.section .note.GNU-stack,"",@progbits
