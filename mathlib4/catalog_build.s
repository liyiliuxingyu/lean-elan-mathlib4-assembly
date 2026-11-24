# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "catalog_layout.inc"
.include "olean_layout.inc"
.bss
.balign 8
.Lview:       .skip VIEW_BYTES
.Lheader:     .skip H_BYTES
.Lmodules:    .skip A_BYTES
.Lrecords:    .skip A_BYTES
.Lslots:      .skip A_BYTES
.Lpool:       .skip A_BYTES
.Lcwd:        .skip 4096
.Lcwdlen:     .skip 8
.Lkind:       .skip 8
.Lsignature:  .skip 8
.Lindexpath:  .skip 8
.text
.globl catalog_build
.hidden catalog_build
.type catalog_build, @function
# (target, count, paths) -> 0 or -1. One-shot CLI builder.
# Input order defines precedence. Querying a duplicate finds the first record.
catalog_build:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rip+.Lindexpath], rdi
    mov [rip+.Lheader+H_MODULES], rsi
    mov r13, rdx
    xor r12d, r12d                   # module number
.Lmodule:
    mov rbx, [r13+r12*8]
    mov rdi, rbx
    lea rsi, [rip+.Lview]
    lea rdx, [rip+.Lsignature]
    call catalog_open_module
    test eax, eax
    jnz .Larchive_error
    lea rdi, [rip+.Lmodules]
    mov esi, M_BYTES
    call catalog_extend
    test rax, rax
    jz .Lfailure
    mov rdx, [rip+.Lpool+A_USED]
    mov [rax+M_PATH], rdx
    mov rdx, [rip+.Lsignature]
    mov [rax+M_SIGNATURE], rdx
    mov rdi, rbx
    call .Lappend_path
    test eax, eax
    jnz .Lfailure
    xor r14d, r14d                   # declaration number within module
.Ldecl:
    cmp r14, [rip+.Lview+VIEW_COUNT]
    je .Lmodule_done
    lea rdi, [rip+.Lview]
    mov rsi, r14
    xor edx, edx
    xor ecx, ecx
    lea r8, [rip+.Lkind]
    call catalog_key_decl
    cmp rax, -3                      # existing query grammar cannot name it
    jne .Lhas_key
    inc qword ptr [rip+.Lheader+H_SKIPPED]
    jmp .Lnext_decl
.Lhas_key:
    test rax, rax
    jle .Larchive_error
    mov r15, rax
    lea rdi, [rip+.Lrecords]
    mov esi, R_BYTES
    call catalog_extend
    test rax, rax
    jz .Lfailure
    mov rbp, rax
    mov rax, [rip+.Lpool+A_USED]
    mov [rbp+R_KEY], rax
    mov [rbp+R_LENGTH], r15
    mov [rbp+R_MODULE], r12
    mov rax, [rip+.Lkind]
    mov [rbp+R_KIND], rax
    lea rdi, [rip+.Lpool]
    mov rsi, r15
    call catalog_extend
    test rax, rax
    jz .Lfailure
    mov rbx, rax
    lea rdi, [rip+.Lview]
    mov rsi, r14
    mov rdx, rbx
    mov rcx, r15
    lea r8, [rip+.Lkind]
    call catalog_key_decl
    cmp rax, r15
    jne .Lfailure
    mov rdi, rbx
    mov rsi, r15
    call asm_zstd_xxh64
    mov [rbp+R_HASH], rax
    inc qword ptr [rip+.Lheader+H_RECORDS]
.Lnext_decl:
    inc r14
    jmp .Ldecl
.Lmodule_done:
    mov rdi, [rip+.Lview+VIEW_MAPPING]
    mov rsi, [rip+.Lview+VIEW_SIZE]
    mov eax, 11
    syscall
    inc r12
    cmp r12, [rip+.Lheader+H_MODULES]
    jb .Lmodule
    mov r12, [rip+.Lheader+H_RECORDS]
    # Record storage already bounded the count to SIZE_MAX / R_BYTES.
    # Choose the first power of two >= twice the declaration count.
    lea rax, [r12+r12]
    mov r14d, 1
.Lcapacity:
    cmp r14, rax
    jae .Lsized
    add r14, r14
    jmp .Lcapacity
.Lsized:
    mov [rip+.Lheader+H_SLOTS], r14
    lea rsi, [r14*8]
    lea rdi, [rip+.Lslots]
    call catalog_extend
    test rax, rax
    jz .Lfailure
    mov r13, rax
    dec r14                          # mask
    mov rbx, [rip+.Lrecords+A_DATA]
    xor r15d, r15d
.Linsert:
    cmp r15, r12
    je .Lserialize
    mov rax, [rbx+R_HASH]
.Lprobe:
    and rax, r14
    cmp qword ptr [r13+rax*8], 0
    je .Lvacant
    inc rax
    jmp .Lprobe
.Lvacant:
    inc r15
    mov [r13+rax*8], r15
    add rbx, R_BYTES
    jmp .Linsert
.Lserialize:
    mov rax, CAT_MAGIC
    mov [rip+.Lheader], rax
    mov rax, [rip+.Lpool+A_USED]
    mov [rip+.Lheader+H_POOL], rax
    add rax, H_BYTES
    add rax, [rip+.Lslots+A_USED]
    add rax, [rip+.Lmodules+A_USED]
    add rax, [rip+.Lrecords+A_USED]
    mov [rip+.Lheader+H_SIZE], rax
    mov rdi, [rip+.Lindexpath]
    lea rsi, [rip+.Lheader]
    lea rdx, [rip+.Lmodules]          # four adjacent arenas, in disk order
    call catalog_save
    jmp .Lreturn
.Larchive_error:
    mov rdx, [r13+r12*8]
    mov eax, -2
    jmp .Lreturn
.Lfailure:
    mov eax, -1
.Lreturn:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size catalog_build, .-catalog_build

# Store an absolute path relative to the builder's working directory. Preserve
# symlink / ".." semantics by retaining the original path components.
.Lappend_path:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    cmp byte ptr [rbx], '/'
    je .Lliteral
    mov r12, [rip+.Lcwdlen]
    test r12, r12
    jnz .Lcopy_cwd
    lea rdi, [rip+.Lcwd]
    mov esi, 4096
    mov eax, 79                       # getcwd includes terminating NUL
    syscall
    cmp rax, 2
    jb .Lpathfail
    test rax, rax
    js .Lpathfail
    lea r12, [rax-1]
    mov [rip+.Lcwdlen], r12
.Lcopy_cwd:
    mov rsi, r12
    # At the filesystem root the cwd already ends in '/'.
    cmp r12, 1
    je .Lprefix
    inc rsi
.Lprefix:
    lea rdi, [rip+.Lpool]
    call catalog_extend
    test rax, rax
    jz .Lpathfail
    mov rdi, rax
    lea rsi, [rip+.Lcwd]
    mov rcx, r12
    rep movsb
    cmp r12, 1
    je .Lliteral
    mov byte ptr [rdi], '/'
.Lliteral:
    mov rdi, rbx
    mov rcx, -1
    xor eax, eax
    repne scasb
    not rcx
    mov r13, rcx
    lea rdi, [rip+.Lpool]
    mov rsi, rcx
    call catalog_extend
    test rax, rax
    jz .Lpathfail
    mov rdi, rax
    mov rsi, rbx
    mov rcx, r13
    rep movsb
    xor eax, eax
    jmp .Lpathret
.Lpathfail:
    mov eax, -1
.Lpathret:
    pop r13
    pop r12
    pop rbx
    ret
.section .note.GNU-stack,"",@progbits
