# SPDX-License-Identifier: Apache-2.0
# Lean 4.19 package-first lookup for the .olean dependency reader.
.intel_syntax noprefix

.equ SYS_newfstatat, 262
.equ AT_FDCWD, -100
.equ ERR_INTR, -4
.equ MODE_TYPE, 0xf000
.equ MODE_DIRECTORY, 0x4000
.equ PATH_LIMIT, 4096
.equ EXT_LENGTH, 6

# The optional caller-owned memo is initially zero and uses stable inputs.
.equ MEMO_PACKAGE, 0
.equ MEMO_PACKAGE_LEN, 8
.equ MEMO_DIRECTORY, 16

.equ PREFIX_LEN, 0
.equ ENTRY_END, 8
.equ SAW_OVERFLOW, 16
.equ MEMO_HIT, 17
.equ FILE_STAT, 32
.equ STAT_MODE, 24
.equ FRAME_BYTES, 184

.section .rodata
.Lempty_search:
    .byte 0

.text
.globl mathlib_olean_resolve
.type mathlib_olean_resolve, @function
# rdi = LEAN_PATH or NULL, rsi = validated relative .olean path,
# rdx = 4096-byte output, rcx = optional zero-initialized 64-byte memo.
# eax = 1 selected, 0 no package owner, -1 invalid or too long.
mathlib_olean_resolve:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME_BYTES
    mov rbp, rsi
    mov r12, rdx
    mov r13, rcx
    mov rbx, rdi
    lea rax, [rip + .Lempty_search]
    test rbx, rbx
    cmovz rbx, rax
    mov byte ptr [rsp + SAW_OVERFLOW], 0
    mov byte ptr [rsp + MEMO_HIT], 0

    # Find the first package component and the full relative path length.
    mov r14d, -1
    xor r15d, r15d
    xor r8d, r8d
.Lrelative_byte:
    cmp r15, PATH_LIMIT
    jae .Linvalid
    mov al, [rbp + r15]
    test al, al
    jz .Lrelative_done
    cmp al, '/'
    jne .Lrelative_next
    mov rax, r15
    call .Lcomponent
    test eax, eax
    jz .Linvalid
    cmp r14d, -1
    cmove r14, r15
    lea r8, [r15 + 1]
.Lrelative_next:
    inc r15
    jmp .Lrelative_byte
.Lrelative_done:
    cmp r15, EXT_LENGTH + 1
    jb .Linvalid
    cmp dword ptr [rbp + r15 - EXT_LENGTH], 0x656c6f2e # .ole
    jne .Linvalid
    cmp word ptr [rbp + r15 - 2], 0x6e61 # an
    jne .Linvalid
    lea rax, [r15 - EXT_LENGTH]
    call .Lcomponent
    test eax, eax
    jz .Linvalid
    lea rax, [r15 - EXT_LENGTH]
    cmp r14d, -1
    cmove r14, rax
    test r14, r14
    jz .Linvalid

    # Adjacent dependencies often belong to one package. Avoid metadata
    # probes when its previously selected search entry is already known.
    test r13, r13
    jz .Lentry
    cmp [r13 + MEMO_PACKAGE_LEN], r14
    jne .Lentry
    mov rsi, [r13 + MEMO_PACKAGE]
    mov rdi, rbp
    mov rcx, r14
    repe cmpsb
    jne .Lentry
    mov rbx, [r13 + MEMO_DIRECTORY]
    mov byte ptr [rsp + MEMO_HIT], 1

.Lentry:
    mov rdx, rbx
.Lentry_byte:
    mov al, [rdx]
    test al, al
    jz .Lentry_end
    cmp al, ':'
    je .Lentry_end
    inc rdx
    jmp .Lentry_byte
.Lentry_end:
    mov [rsp + ENTRY_END], rdx
    sub rdx, rbx
    mov rcx, rdx
    test rcx, rcx
    jz .Lprefix_ready
    cmp byte ptr [rbx + rcx - 1], '/'
    je .Lprefix_ready
    inc rcx
.Lprefix_ready:
    mov [rsp + PREFIX_LEN], rcx
    mov rax, r14
    cmp byte ptr [rsp + MEMO_HIT], 0
    cmovne rax, r15
    add rax, rcx
    cmp rax, PATH_LIMIT
    jae .Loverlong_entry

    # Copy this root with exactly one separating slash when needed.
    mov rdi, r12
    mov rsi, rbx
    mov rcx, rdx
    rep movsb
    cmp rdx, [rsp + PREFIX_LEN]
    je .Lprefix_written
    mov byte ptr [rdi], '/'
    inc rdi
.Lprefix_written:
    cmp byte ptr [rsp + MEMO_HIT], 0
    jne .Lowner

    # Lean selects the first package directory or package.olean marker.
    # The requested child is only opened after the selection is complete.
    mov rsi, rbp
    mov rcx, r14
    rep movsb
    mov byte ptr [rdi], 0
    call .Lprobe
    test rax, rax
    js .Lmarker
    mov eax, [rsp + FILE_STAT + STAT_MODE]
    and eax, MODE_TYPE
    cmp eax, MODE_DIRECTORY
    je .Lowner

.Lmarker:
    mov rax, [rsp + PREFIX_LEN]
    lea rax, [rax + r14]
    cmp rax, PATH_LIMIT - EXT_LENGTH
    jae .Loverlong_entry
    mov dword ptr [r12 + rax], 0x656c6f2e
    mov word ptr [r12 + rax + 4], 0x6e61
    mov byte ptr [r12 + rax + EXT_LENGTH], 0
    call .Lprobe
    test rax, rax
    jns .Lowner
    jmp .Lnext_entry

.Loverlong_entry:
    cmp byte ptr [rsp + MEMO_HIT], 0
    jne .Linvalid
    mov byte ptr [rsp + SAW_OVERFLOW], 1
.Lnext_entry:
    mov rax, [rsp + ENTRY_END]
    cmp byte ptr [rax], 0
    je .Lno_more_entries
    lea rbx, [rax + 1]
    jmp .Lentry
.Lno_more_entries:
    cmp byte ptr [rsp + SAW_OVERFLOW], 0
    jne .Linvalid
    xor eax, eax
    jmp .Lfinish

.Lowner:
    mov rax, [rsp + PREFIX_LEN]
    lea rdx, [rax + r15]
    cmp rdx, PATH_LIMIT
    jae .Linvalid
    lea rdi, [r12 + rax]
    mov rsi, rbp
    lea rcx, [r15 + 1]
    rep movsb
    test r13, r13
    jz .Lresolved
    mov [r13 + MEMO_PACKAGE], rbp
    mov [r13 + MEMO_PACKAGE_LEN], r14
    mov [r13 + MEMO_DIRECTORY], rbx
.Lresolved:
    mov eax, 1
    jmp .Lfinish

.Linvalid:
    mov eax, -1
.Lfinish:
    add rsp, FRAME_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.Lprobe:
    mov edi, AT_FDCWD
    mov rsi, r12
    lea rdx, [rsp + FILE_STAT + 8]
    xor r10d, r10d
.Lretry_probe:
    mov eax, SYS_newfstatat
    syscall
    cmp rax, ERR_INTR
    je .Lretry_probe
    ret

# Check [r8, rax) for a nonempty component other than "." or "..".
.Lcomponent:
    sub rax, r8
    jbe .Lbad_component
    cmp rax, 2
    ja .Lgood_component
    jne .Lsingle_byte
    cmp word ptr [rbp + r8], 0x2e2e
    jne .Lgood_component
    jmp .Lbad_component
.Lsingle_byte:
    cmp byte ptr [rbp + r8], '.'
    je .Lbad_component
.Lgood_component:
    mov eax, 1
    ret
.Lbad_component:
    xor eax, eax
    ret
.size mathlib_olean_resolve, . - mathlib_olean_resolve

.section .note.GNU-stack,"",@progbits
