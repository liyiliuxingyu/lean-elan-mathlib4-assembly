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
.equ SYS_GETCWD, 79
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
    call    .Lstrlen
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
    test    rcx, rcx
    jz      .Lnext_command_byte
    cmp     al, '.'
    jne     .Lnext_command_byte
    mov     byte ptr [rip+.Lhas_extension], 1
.Lnext_command_byte:
    inc     rcx
    jmp     .Lscan_command_byte

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
    call    .Lread_u32
    cmp     eax, 5
    ja      .Lrecursion_limit
    add     al, '1'
    mov     [rip+.Lrecursion_digit], al

    xor     r8d, r8d
    mov     rbx, [rip+.Lenv_values+ENV_ELAN_HOME*8]
    test    rbx, rbx
    jnz     .Lhome_input
    mov     rbx, [rip+.Lenv_values+ENV_HOME*8]
    test    rbx, rbx
    jz      .Lmissing_home
    cmp     byte ptr [rbx], 0
    je      .Lmissing_home
    mov     r8d, 1                  /* append .elan to HOME */
.Lhome_input:
    lea     rdi, [rip+.Lhome]
    lea     rdx, [rip+.Lhome+PATH_CAPACITY]
    mov     rsi, rbx
    cmp     byte ptr [rbx], '/'
    je      .Lcopy_home
    mov     esi, PATH_CAPACITY
    mov     eax, SYS_GETCWD
    syscall
    test    rax, rax
    js      .Lbad_cwd
    lea     rdi, [rdi+rax-1]       /* getcwd length includes NUL */
    mov     rsi, rbx
    call    .Ljoin_component
    jmp     .Lhome_suffix
.Lcopy_home:
    call    .Lappend_z
.Lhome_suffix:
    jc      .Ltoo_long
    test    r8d, r8d
    jz      .Lhome_ready
    lea     rsi, [rip+.Ldot_elan]
    call    .Ljoin_component
    jc      .Ltoo_long

.Lhome_ready:
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
    cmp     dword ptr [rip+.Ldesc], 3
    jne     .Linstalled_toolchain
    mov     rsi, r12
    call    .Lappend_z
    jc      .Ltoo_long
    jmp     .Lprogram_bin
.Linstalled_toolchain:
    lea     rsi, [rip+.Lhome]
    call    .Lappend_z
    jc      .Ltoo_long
    lea     rsi, [rip+.Ltoolchains]
    call    .Ljoin_component
    jc      .Ltoo_long
    /* Existing directory name encoding: / becomes -- and : becomes ---. */
    cmp     rdi, rdx
    jae     .Ltoo_long
    mov     byte ptr [rdi], '/'
    inc     rdi
    mov     rsi, r12
.Lencode_descriptor:
    cmp     rdi, rdx
    jae     .Ltoo_long
    lodsb
    cmp     al, '/'
    je      .Lencode_pair
    cmp     al, ':'
    je      .Lencode_triple
    mov     [rdi], al
    test    al, al
    jz      .Lprogram_bin
    inc     rdi
    jmp     .Lencode_descriptor
.Lencode_triple:
    mov     byte ptr [rdi], '-'
    inc     rdi
    cmp     rdi, rdx
    jae     .Ltoo_long
.Lencode_pair:
    mov     byte ptr [rdi], '-'
    inc     rdi
    cmp     rdi, rdx
    jae     .Ltoo_long
    mov     byte ptr [rdi], '-'
    inc     rdi
    jmp     .Lencode_descriptor
.Lprogram_bin:
    lea     rsi, [rip+.Lbin]
    call    .Ljoin_component
    jc      .Ltoo_long
    mov     rsi, r15
    call    .Ljoin_component
    jc      .Ltoo_long
    cmp     byte ptr [rip+.Lhas_extension], 0
    jne     .Lbuild_home_env
    /* The staged Linux port folds ASCII in extensionless basenames. */
    mov     rcx, r15
.Lwalk_basename:
    cmp     byte ptr [rcx], 0
    je      .Lfold_basename
    inc     rcx
    jmp     .Lwalk_basename
.Lfold_basename:
    sub     rcx, r15
    sub     rdi, rcx
.Lfold_byte:
    mov     al, [rdi]
    test    al, al
    jz      .Lbuild_home_env
    cmp     al, 'A'
    jb      .Lfold_next
    cmp     al, 'Z'
    ja      .Lfold_next
    or      byte ptr [rdi], 32
.Lfold_next:
    inc     rdi
    jmp     .Lfold_byte

.Lbuild_home_env:
    lea     rdi, [rip+.Lhome_env]
    lea     rdx, [rip+.Lhome_env+PATH_CAPACITY+10]
    lea     rsi, [rip+.Lkey_elan_home]
    call    .Lappend_z
    lea     rsi, [rip+.Lhome]
    call    .Lappend_z
    jc      .Ltoo_long

    lea     rdi, [rip+.Ltoolchain_env]
    lea     rdx, [rip+.Ltoolchain_env+PATH_CAPACITY+15]
    lea     rsi, [rip+.Lkey_toolchain]
    call    .Lappend_z
    mov     rsi, r12
    call    .Lappend_z
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
    call    .Lappend_z
    lea     rsi, [rip+.Lhome]
    call    .Lappend_z
    jc      .Ltoo_long
    lea     rsi, [rip+.Lbin]
    call    .Ljoin_component
    jc      .Ltoo_long
    mov     rsi, [rip+.Lenv_values+ENV_PATH*8]
    test    rsi, rsi
    jz      .Lbuild_env_vector
    mov     byte ptr [rdi], ':'
    inc     rdi
    call    .Lappend_z
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
.size _start, .-_start

.ifdef AUTO_SELECT
/* Shared bounded path/string operations used by the selection front end. */
.globl elan_strlen, elan_join_component, elan_append_z
.set elan_strlen, .Lstrlen
.set elan_join_component, .Ljoin_component
.set elan_append_z, .Lappend_z
.endif

/* rdi = NUL-terminated input; rax = length. */
.Lstrlen:
    xor     eax, eax
.Lstrlen_byte:
    cmp     byte ptr [rdi+rax], 0
    je      .Lstrlen_done
    inc     rax
    jmp     .Lstrlen_byte
.Lstrlen_done:
    ret

/* Append a NUL-terminated component, adding a separator when needed. */
.Ljoin_component:
    cmp     byte ptr [rsi], 0
    je      .Lappend_z
    cmp     byte ptr [rdi-1], '/'
    je      .Lappend_z
    cmp     rdi, rdx
    jae     .Lappend_full
    mov     byte ptr [rdi], '/'
    inc     rdi
/* rdi = destination cursor; rsi = source; rdx = destination bound.
 * On success rdi points to the terminating NUL and CF is clear.
 */
.Lappend_z:
    cmp     rdi, rdx
    jae     .Lappend_full
    lodsb
    mov     [rdi], al
    test    al, al
    jz      .Lappend_done
    inc     rdi
    jmp     .Lappend_z
.Lappend_done:
    clc
    ret
.Lappend_full:
    stc
    ret

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

/* Optional + followed by decimal digits in u32 range. Invalid input is 0. */
.Lread_u32:
    xor     eax, eax
    test    rsi, rsi
    jz      .Lu32_done
    cmp     byte ptr [rsi], '+'
    jne     .Lu32_digit
    inc     rsi
.Lu32_digit:
    movzx   ecx, byte ptr [rsi]
    test    ecx, ecx
    jz      .Lu32_done
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .Lu32_invalid
    imul    rax, rax, 10
    add     rax, rcx
    mov     rcx, rax
    shr     rcx, 32
    jnz     .Lu32_invalid
    inc     rsi
    jmp     .Lu32_digit
.Lu32_invalid:
    xor     eax, eax
.Lu32_done:
    ret

.section .rodata
.Ldot_elan:   .asciz ".elan"
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
    .asciz "1"

.section .bss
.balign 8
.Ldesc:          .skip 40
.Lenv_values:    .skip ENV_SLOTS*8
.Lhome:          .skip PATH_CAPACITY
.Lprogram:       .skip PATH_CAPACITY
.Lhome_env:      .skip PATH_CAPACITY+10
.Ltoolchain_env: .skip PATH_CAPACITY+15
.Lpath_env:      .skip ENV_PATH_CAPACITY
.Lhas_extension: .skip 1

.section .note.GNU-stack,"",@progbits
