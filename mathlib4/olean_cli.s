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
.equ PROT_WRITE, 2
.equ MAP_PRIVATE, 2
.equ MAP_ANONYMOUS, 0x20
.equ EINTR, 4
.equ S_IFMT, 0xf000
.equ S_IFREG, 0x8000

.equ decimal_end, VIEW_BYTES + RESULT_BYTES + 32
.equ stat_mode, 24
.equ stat_size, 48
.equ stack_size, 160
.equ error_path, stack_size
.equ error_path_capacity, 4096
.equ recursive_stack_size, stack_size + error_path_capacity

.text
.globl _start
.type _start, @function
_start:
    xor r12d, r12d          # Accumulated exit status.
    xor r15d, r15d          # Owned mapping for file data or recursive results.
    mov r13, [rsp]          # Names left after removing program and path.
    sub r13, 2
    jb .Lusage_error
    mov rsi, [rsp + 16]
    lea rdi, [rip + .Lrecursive_option]
    mov ecx, OFFSET FLAT:.Lrecursive_option_length
    repe cmpsb
    je .Lrecursive
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
    xor ebp, ebp            # A zero result cursor selects the single-file lookup.
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
    test rbp, rbp
    jnz .Lrecursive_query
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
.Lrender_kind:
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

.Lrecursive:
    sub r13, 1             # Exclude the option, leaving strictly one or more names.
    jbe .Lrecursive_usage_error
    mov rbp, [rsp + 24]    # Root path until the search returns.
    lea rbx, [rsp + 32]    # First query.
    lea rsi, [rbx + r13*8 + 8] # Environment follows argv's null pointer.
    lea r8, [rip + .Llean_path_prefix]
.Lenvironment:
    mov rdx, [rsi]
    test rdx, rdx
    jz .Lenvironment_done
    xor ecx, ecx
.Lenvironment_prefix:
    mov al, [rdx + rcx]
    cmp al, [r8 + rcx]
    jne .Lnext_environment
    inc rcx
    cmp ecx, OFFSET FLAT:.Llean_path_prefix_length
    jb .Lenvironment_prefix
    add rdx, rcx
    jmp .Lenvironment_done
.Lnext_environment:
    add rsi, 8
    jmp .Lenvironment

.Lenvironment_done:
    and rsp, -16
    sub rsp, recursive_stack_size
    mov [rsp], rdx          # LEAN_PATH, or null when absent.
    xor edi, edi
    mov rsi, r13           # One result byte for each argument.
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8d, -1
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    cmp rax, -4095
    jae .Lworkspace_error
    mov r15, rax
    mov r14, r13

    mov rdi, rbp
    mov rsi, [rsp]
    mov rdx, r13
    mov rcx, rbx
    mov r8, r15
    lea r9, [rsp + error_path]
    mov BYTE PTR [r9], 0
    call mathlib_olean_search_graph
    test eax, eax
    jz .Lrecursive_ready
    cmp eax, -1
    je .Lquery_error
    cmp eax, -2
    je .Lcache_error
    cmp eax, -3
    je .Ldependency_error
    jmp .Lworkspace_error

.Lrecursive_ready:
    mov rbp, r15
.Lrecursive_query:
    movzx edx, BYTE PTR [rbp]
    inc rbp
    sub edx, 1
    jb .Lmissing
    jmp .Lrender_kind

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
.Lrecursive_usage_error:
    lea rsi, [rip + .Lrecursive_usage_message]
    mov edx, OFFSET FLAT:.Lrecursive_usage_message_len
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
.Ldependency_error:
    lea rdx, [rsp + error_path]
    xor ecx, ecx
.Ldependency_path_length:
    cmp BYTE PTR [rdx + rcx], 0
    je .Ldependency_path_ready
    inc ecx
    cmp ecx, error_path_capacity
    jb .Ldependency_path_length
    jmp .Ldependency_error_generic
.Ldependency_path_ready:
    test ecx, ecx
    jz .Ldependency_error_generic
    lea rdi, [rip + .Ldependency_prefix]
    mov esi, OFFSET FLAT:.Ldependency_prefix_len
    mov r8d, 2
    call .Lwrite_record_fd
    mov r12d, 2
    jmp .Lfinish
.Ldependency_error_generic:
    lea rsi, [rip + .Ldependency_message]
    mov edx, OFFSET FLAT:.Ldependency_message_len
    jmp .Lreport_error
.Lworkspace_error:
    lea rsi, [rip + .Lworkspace_message]
    mov edx, OFFSET FLAT:.Lworkspace_message_len
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
    mov r8d, 1
.Lwrite_record_fd:
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
    mov edi, r8d

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
.Lrecursive_option:
    .asciz "--recursive"
.equ .Lrecursive_option_length, . - .Lrecursive_option
.Llean_path_prefix:
    .ascii "LEAN_PATH="
.equ .Llean_path_prefix_length, . - .Llean_path_prefix

OLEAN_STRING .Lusage_message, "usage: mathlib-olean FILE.olean [QUALIFIED_NAME ...]\n"
OLEAN_STRING .Lrecursive_usage_message, "usage: mathlib-olean --recursive FILE.olean QUALIFIED_NAME [...]\n"
OLEAN_STRING .Lopen_message, "mathlib-olean: cannot open cache (check the path and permissions)\n"
OLEAN_STRING .Lbad_file_message, "mathlib-olean: cache must be a readable regular file\n"
OLEAN_STRING .Lmap_message, "mathlib-olean: cannot map cache read-only\n"
OLEAN_STRING .Lcache_message, "mathlib-olean: incompatible or malformed cache (expected Lean 4.19.0 x86-64 GMP)\n"
OLEAN_STRING .Lquery_message, "mathlib-olean: invalid qualified name (expected nonempty dot-separated components)\n"
OLEAN_STRING .Ldependency_message, "mathlib-olean: cannot read required cache (check the root path and LEAN_PATH)\n"
OLEAN_STRING .Ldependency_prefix, "mathlib-olean: cannot read required cache (check LEAN_PATH): "
OLEAN_STRING .Lworkspace_message, "mathlib-olean: recursive search exceeded a path or workspace limit\n"
OLEAN_STRING .Loutput_message, "mathlib-olean: failed to write output\n"

.section .note.GNU-stack,"",@progbits
