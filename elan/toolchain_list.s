/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Elan Cfg::list_toolchains and CLI output. Linux x86-64 stat and dirent64. */
.intel_syntax noprefix
.equ SYS_open, 2
.equ SYS_stat, 4
.equ SYS_mmap, 9
.equ SYS_getdents64, 217
.equ SYS_newfstatat, 262
.equ DIRECTORY, 0x4000
.equ FILE_TYPE, 0xf000
.equ AT_SYMLINK_NOFOLLOW, 0x100
.equ CHUNK, 65536

/* Linked merge-sort node: next pointer, key length, name pointer, key bytes.
 * Equal keys retain getdents order, matching Rust's stable sort. */
.equ NEXT, 0
.equ KEYLEN, 8
.equ NAME, 16
.equ KEY, 24

.text
.globl elan_list_toolchains
.type elan_list_toolchains,@function
/* (rdi = toolchains path). Called once per process. */
elan_list_toolchains:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    lea rsi, [rip+.Lstat]
    mov eax, SYS_stat
    syscall
    test rax, rax
    js .Lempty
    mov eax, [rsi+24]
    and eax, FILE_TYPE
    cmp eax, DIRECTORY
    jne .Lempty
    mov esi, 0x10000                /* O_RDONLY | O_DIRECTORY */
    mov eax, SYS_open
    syscall
    test rax, rax
    js .Lread_error
    mov ebx, eax
.Lread:
    mov edi, ebx
    lea rsi, [rip+.Lentries]
    mov edx, 32768
    mov eax, SYS_getdents64
    syscall
    cmp rax, -4
    je .Lread
    test rax, rax
    js .Lread_error
    jz .Lfinish
    mov r13, rsi                    /* cursor */
    lea r14, [rsi+rax]              /* end of kernel-provided records */
.Lentry:
    lea r15, [r13+19]               /* d_name */
    movzx eax, byte ptr [r13+18]    /* d_type (unfollowed) */
    movzx ecx, word ptr [r13+16]    /* d_reclen */
    add r13, rcx
    cmp al, 8                       /* DT_REG */
    je .Lnext_entry
    test al, al
    jnz .Lcheck_name
    /* DT_UNKNOWN on some filesystems. Use the opened directory handle. */
    mov edi, ebx
    mov rsi, r15
    lea rdx, [rip+.Lstat]
    mov r10d, AT_SYMLINK_NOFOLLOW
    mov eax, SYS_newfstatat
    syscall
    test rax, rax
    js .Lnext_entry
    mov eax, [rdx+24]
    and eax, FILE_TYPE
    cmp eax, 0x8000
    je .Lnext_entry
.Lcheck_name:
    cmp word ptr [r15], '.'
    je .Lnext_entry
    cmp word ptr [r15], 0x2e2e
    jne .Lvalidate
    cmp byte ptr [r15+2], 0
    je .Lnext_entry
.Lvalidate:
    mov rdi, r15
    call elan_strlen
    mov rsi, rax
    call elan_manage_utf8
    test eax, eax
    jz .Lnext_entry                 /* OsString::into_string().ok() */
    mov rdi, r15
    call elan_strlen
    mov rsi, rax
    lea rdx, [rip+.Ldecoded]
    mov ecx, 255                    /* Linux NAME_MAX */
    call elan_decode_toolchain_dir
    test rax, rax
    js .Lresource_error
    lea rdi, [rip+.Ldecoded]
    mov byte ptr [rdi+rax], 0
    mov rsi, rax
    lea rdx, [rip+.Ldesc]
    call elan_parse_resolved
    test eax, eax
    jz .Linvalid_name
    call .Linsert
.Lnext_entry:
    cmp r13, r14
    jb .Lentry
    jmp .Lread
.Lfinish:
    mov edi, ebx
    mov eax, 3                     /* close */
    syscall
    lea r13, [rip+.Lbins]
    lea r14, [r13+64*8]
    xor ebx, ebx
.Lfold:
    mov rdi, [r13]
    test rdi, rdi
    jz .Lfold_next
    mov rsi, rbx
    call .Lmerge
    mov rbx, rax
.Lfold_next:
    add r13, 8
    cmp r13, r14
    jb .Lfold
    test rbx, rbx
    jz .Lempty
.Lprint:
    mov edi, 1
    mov rsi, [rbx+NAME]
    call elan_manage_write
    mov edi, 1
    lea rsi, [rip+.Lnewline]
    call elan_manage_write
    mov rbx, [rbx+NEXT]
    test rbx, rbx
    jnz .Lprint
    jmp .Ldone
.Lempty:
    mov edi, 1
    lea rsi, [rip+.Lnone]
    call elan_manage_write
.Ldone:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lread_error:
    mov edx, eax
    lea rdi, [rip+.Lcannot_read]
    mov rsi, r12
    jmp elan_manage_io_error
.Linvalid_name:
    lea rdi, [rip+.Linvalid]
    lea rsi, [rip+.Ldecoded]
    lea rdx, [rip+.Lquote_end]
    jmp elan_manage_error
.Lresource_error:
    mov edi, 2
    lea rsi, [rip+.Lno_memory]
    call elan_manage_write
    jmp elan_manage_fail
.size elan_list_toolchains, .-elan_list_toolchains

/* Materialize a sort node in a growing arena. The directory entries and
 * temporary sort key may then be reused as soon as this function returns. */
.Linsert:
    push rbx
    push r12
    push r13
    lea rdi, [rip+.Ldecoded]
    call elan_strlen
    lea r13, [rax+1]
    lea rsi, [rip+.Lkey]
    call elan_toolchain_order_key
    mov r12, rax
    lea rbx, [r13+rax+KEY+7]
    and rbx, -8
    mov rdi, [rip+.Larena]
    lea rax, [rdi+rbx]
    cmp rax, [rip+.Llimit]
    jbe .Lhave_space
    xor edi, edi
    mov esi, CHUNK
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    cmp rax, -4095
    jae .Lresource_error
    mov rdi, rax
    lea rax, [rdi+CHUNK]
    mov [rip+.Llimit], rax
    lea rax, [rdi+rbx]
.Lhave_space:
    mov [rip+.Larena], rax
    mov rbx, rdi
    mov qword ptr [rbx+NEXT], 0
    mov [rbx+KEYLEN], r12
    lea rdi, [rbx+KEY]
    lea rsi, [rip+.Lkey]
    mov rcx, r12
    rep movsb
    mov [rbx+NAME], rdi
    lea rsi, [rip+.Ldecoded]
    mov rcx, r13
    rep movsb
    lea r12, [rip+.Lbins]
.Lcarry:
    mov rdi, [r12]
    test rdi, rdi
    jz .Lstore_bin
    mov qword ptr [r12], 0
    mov rsi, rbx
    call .Lmerge
    mov rbx, rax
    add r12, 8
    jmp .Lcarry
.Lstore_bin:
    mov [r12], rbx
    pop r13
    pop r12
    pop rbx
    ret

/* (rdi = earlier run, rsi = later run) -> rax = merged head. */
.Lmerge:
    mov r8, rdi
    mov r9, rsi
    sub rsp, 8
    mov r10, rsp
.Lcompare:
    test r8, r8
    jz .Lleft_empty
    test r9, r9
    jz .Lright_empty
    mov rcx, [r8+KEYLEN]
    cmp rcx, [r9+KEYLEN]
    cmova rcx, [r9+KEYLEN]
    lea rsi, [r8+KEY]
    lea rdi, [r9+KEY]
    repe cmpsb
    /* Encoded keys are self-delimiting; a byte prefix implies equality. */
    ja .Ltake_right
    mov [r10], r8
    mov r10, r8
    mov r8, [r8+NEXT]
    jmp .Lcompare
.Ltake_right:
    mov [r10], r9
    mov r10, r9
    mov r9, [r9+NEXT]
    jmp .Lcompare
.Lleft_empty:
    mov r8, r9
.Lright_empty:
    mov [r10], r8
    pop rax
    ret

.section .rodata
.Lnone:        .asciz "no installed toolchains\n"
.Lnewline:     .asciz "\n"
.Lcannot_read: .asciz "error: could not read toolchains directory: '"
.Linvalid:     .asciz "error: invalid toolchain name: '"
.Lquote_end:   .asciz "'\n"
.Lno_memory:   .asciz "error: cannot allocate toolchain list\n"
.section .bss
.balign 8
.Lbins:    .skip 64*8
.Larena:   .skip 8
.Llimit:   .skip 8
.Lstat:    .skip 144
.Ldesc:    .skip 40
.Lentries: .skip 32768
.Ldecoded: .skip 256
.Lkey:     .skip 2614
.section .note.GNU-stack,"",@progbits
