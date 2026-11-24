# SPDX-License-Identifier: Apache-2.0
# A Linux x86-64 CLI over the read-only olean parser. No runtime libraries.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ SYS_write,   1
.equ SYS_close,   3
.equ SYS_fstat,   5
.equ SYS_mmap,    9
.equ SYS_munmap, 11
.equ SYS_writev, 20
.equ SYS_exit,   60
.equ SYS_openat, 257

.equ AT_FDCWD, -100
.equ O_NONBLOCK, 0x800
.equ O_CLOEXEC, 0x80000
.equ PROT_READ, 1
.equ MAP_PRIVATE, 2
.equ EINTR, 4
.equ S_IFMT, 0xf000
.equ S_IFREG, 0x8000

.equ decimal_end, VIEW_BYTES + RESULT_BYTES + 32
.equ stat_mode, 24
.equ stat_size, 48
.equ stack_size, 160

.text
.globl _start
.type _start, @function
_start:
    xor r12d, r12d          # Accumulated exit status.
    xor r15d, r15d          # File mapping, once owned.
    mov r13, [rsp]          # Names left after removing program and path.
    sub r13, 2
    jb .Lusage_error
    mov rsi, [rsp + 16]     # Path.
    lea rbx, [rsp + 24]     # Next name argument.
    and rsp, -16
    sub rsp, stack_size

    mov edi, AT_FDCWD
    mov edx, O_NONBLOCK | O_CLOEXEC
    xor r10d, r10d
.Lopen:
    mov eax, SYS_openat
    syscall
    cmp rax, -EINTR
    je .Lopen
    test rax, rax
    js .Lopen_error
    mov ebp, eax

    mov edi, ebp
    mov rsi, rsp
.Lstat:
    mov eax, SYS_fstat
    syscall
    cmp rax, -EINTR
    je .Lstat
    test rax, rax
    js .Lclose_bad_file
    mov eax, [rsp + stat_mode]
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Lclose_bad_file
    mov r14, [rsp + stat_size]
    cmp r14, 96
    jl .Lclose_bad_cache

    xor edi, edi
    mov rsi, r14
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8d, ebp
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    mov r15, rax
    mov edi, ebp
    mov eax, SYS_close
    syscall
    cmp r15, -4095
    jae .Lmap_error

    mov rdi, r15
    mov rsi, r14
    mov rdx, rsp
    call mathlib_olean_parse
    cmp eax, 1
    jne .Lcache_error
    test r13, r13
    jz .Lsummary

.Lquery:
    mov rdi, rsp
    mov rsi, [rbx]
    lea rdx, [rsp + VIEW_BYTES]
    call mathlib_olean_lookup
    cmp eax, 1
    je .Lmatch
    test eax, eax
    jz .Lmissing
    cmp eax, -1
    je .Lquery_error
    jmp .Lcache_error

.Lmatch:
    mov rdx, [rsp + VIEW_BYTES + RESULT_KIND]
    cmp rdx, 7
    ja .Lcache_error
    lea rdi, [rip + .Lkinds]
    mov esi, [rdi + rdx*8 + 4]
    movsxd rdx, DWORD PTR [rdi + rdx*8]
    add rdi, rdx
    jmp .Lprint_name

.Lmissing:
    mov r12d, 1
    lea rdi, [rip + .Lmissing_prefix]
    mov esi, OFFSET FLAT:.Lmissing_prefix_len

.Lprint_name:
    mov rdx, [rbx]
    xor ecx, ecx
.Lname_length:
    cmp BYTE PTR [rdx + rcx], 0
    je .Lemit_name
    inc rcx
    jmp .Lname_length
.Lemit_name:
    call .Lwrite_record
    test eax, eax
    jnz .Loutput_error
    add rbx, 8
    dec r13
    jnz .Lquery
    jmp .Lfinish

.Lsummary:
    mov rax, [rsp + VIEW_COUNT]
    lea rsi, [rsp + decimal_end]
    call .Ldecimal
    lea rdi, [rip + .Ldeclarations_prefix]
    mov esi, OFFSET FLAT:.Ldeclarations_prefix_len
    call .Lwrite_record
    test eax, eax
    jnz .Loutput_error

    mov rax, [rsp + VIEW_IMPORTS]
    lea rsi, [rsp + decimal_end]
    call .Ldecimal
    lea rdi, [rip + .Limports_prefix]
    mov esi, OFFSET FLAT:.Limports_prefix_len
    call .Lwrite_record
    test eax, eax
    jnz .Loutput_error
    jmp .Lfinish

.Lclose_bad_file:
    mov edi, ebp
    mov eax, SYS_close
    syscall
    lea rsi, [rip + .Lbad_file_message]
    mov edx, OFFSET FLAT:.Lbad_file_message_len
    jmp .Lreport_error

.Lclose_bad_cache:
    mov edi, ebp
    mov eax, SYS_close
    syscall
    jmp .Lcache_error

.Lusage_error:
    lea rsi, [rip + .Lusage_message]
    mov edx, OFFSET FLAT:.Lusage_message_len
    jmp .Lreport_error
.Lopen_error:
    lea rsi, [rip + .Lopen_message]
    mov edx, OFFSET FLAT:.Lopen_message_len
    jmp .Lreport_error
.Lmap_error:
    xor r15d, r15d
    lea rsi, [rip + .Lmap_message]
    mov edx, OFFSET FLAT:.Lmap_message_len
    jmp .Lreport_error
.Lcache_error:
    lea rsi, [rip + .Lcache_message]
    mov edx, OFFSET FLAT:.Lcache_message_len
    jmp .Lreport_error
.Lquery_error:
    lea rsi, [rip + .Lquery_message]
    mov edx, OFFSET FLAT:.Lquery_message_len
    jmp .Lreport_error
.Loutput_error:
    lea rsi, [rip + .Loutput_message]
    mov edx, OFFSET FLAT:.Loutput_message_len

.Lreport_error:
    mov r12d, 2
    mov edi, 2
.Lwrite_error:
    mov eax, SYS_write
    syscall
    cmp rax, -EINTR
    je .Lwrite_error
    test rax, rax
    jle .Lfinish
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite_error

.Lfinish:
    test r15, r15
    jz .Lexit
    mov rdi, r15
    mov rsi, r14
    mov eax, SYS_munmap
    syscall
.Lexit:
    mov edi, r12d
    mov eax, SYS_exit
    syscall
    ud2
.size _start, . - _start

# Format rax (unsigned) backwards from rsi. Return start in rdx and size in rcx.
.type .Ldecimal, @function
.Ldecimal:
    mov r8, rsi
    mov r9d, 10
.Ldigit:
    xor edx, edx
    div r9
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .Ldigit
    mov rdx, rsi
    mov rcx, r8
    sub rcx, rsi
    ret
.size .Ldecimal, . - .Ldecimal

# Write prefix (rdi/rsi) and value (rdx/rcx) with a newline using one writev.
# Retry short writes and interrupts. Return 0 on success and 1 on failure.
.type .Lwrite_record, @function
.Lwrite_record:
    sub rsp, 48
    mov [rsp], rdi
    mov [rsp + 8], rsi
    mov [rsp + 16], rdx
    mov [rsp + 24], rcx
    lea rax, [rip + .Lnewline]
    mov [rsp + 32], rax
    mov QWORD PTR [rsp + 40], 1
    mov rsi, rsp
    mov edx, 3
    mov edi, 1

.Lwrite_record_retry:
    mov eax, SYS_writev
    syscall
    cmp rax, -EINTR
    je .Lwrite_record_retry
    test rax, rax
    jle .Lwrite_record_failed

.Lwrite_record_advance:
    cmp rax, [rsi + 8]
    jb .Lwrite_record_partial
    sub rax, [rsi + 8]
    add rsi, 16
    dec edx
    jnz .Lwrite_record_advance
    xor eax, eax
    jmp .Lwrite_record_return

.Lwrite_record_partial:
    add [rsi], rax
    sub [rsi + 8], rax
    jmp .Lwrite_record_retry

.Lwrite_record_failed:
    mov eax, 1
.Lwrite_record_return:
    add rsp, 48
    ret
.size .Lwrite_record, . - .Lwrite_record

.section .rodata
.balign 4
.Lkinds:
    .long .Laxiom_prefix - .Lkinds, .Laxiom_prefix_len
    .long .Ldefinition_prefix - .Lkinds, .Ldefinition_prefix_len
    .long .Ltheorem_prefix - .Lkinds, .Ltheorem_prefix_len
    .long .Lopaque_prefix - .Lkinds, .Lopaque_prefix_len
    .long .Lquotient_prefix - .Lkinds, .Lquotient_prefix_len
    .long .Linductive_prefix - .Lkinds, .Linductive_prefix_len
    .long .Lconstructor_prefix - .Lkinds, .Lconstructor_prefix_len
    .long .Lrecursor_prefix - .Lkinds, .Lrecursor_prefix_len

.macro OLEAN_STRING label, value:vararg
\label:
    .ascii \value
    .equ \label\()_len, . - \label
.endm

OLEAN_STRING .Laxiom_prefix, "axiom\t"
OLEAN_STRING .Ldefinition_prefix, "definition\t"
OLEAN_STRING .Ltheorem_prefix, "theorem\t"
OLEAN_STRING .Lopaque_prefix, "opaque\t"
OLEAN_STRING .Lquotient_prefix, "quotient\t"
OLEAN_STRING .Linductive_prefix, "inductive\t"
OLEAN_STRING .Lconstructor_prefix, "constructor\t"
OLEAN_STRING .Lrecursor_prefix, "recursor\t"
OLEAN_STRING .Lmissing_prefix, "missing\t"
OLEAN_STRING .Ldeclarations_prefix, "declarations\t"
OLEAN_STRING .Limports_prefix, "imports\t"
.Lnewline:
    .byte 10

OLEAN_STRING .Lusage_message, "usage: mathlib-olean FILE.olean [QUALIFIED_NAME ...]\n"
OLEAN_STRING .Lopen_message, "mathlib-olean: cannot open cache (check the path and permissions)\n"
OLEAN_STRING .Lbad_file_message, "mathlib-olean: cache must be a readable regular file\n"
OLEAN_STRING .Lmap_message, "mathlib-olean: cannot map cache read-only\n"
OLEAN_STRING .Lcache_message, "mathlib-olean: incompatible or malformed cache (expected Lean 4.19.0 x86-64 GMP)\n"
OLEAN_STRING .Lquery_message, "mathlib-olean: invalid qualified name (expected nonempty dot-separated components)\n"
OLEAN_STRING .Loutput_message, "mathlib-olean: failed to write output\n"

.section .note.GNU-stack,"",@progbits
