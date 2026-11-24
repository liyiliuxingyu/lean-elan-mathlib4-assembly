# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "catalog_layout.inc"
.text
.globl catalog_view
.hidden catalog_view
.type catalog_view, @function
# (mapping,length,view) -> 0/-1. Section arithmetic is checked up front.
# Individual probe records are then checked against these sections on use.
catalog_view:
    cmp rsi, H_BYTES
    jb .Linvalid
    mov rax, CAT_MAGIC
    cmp [rdi], rax
    jne .Linvalid
    cmp [rdi+H_SIZE], rsi
    jne .Linvalid
    cmp qword ptr [rdi+56], 0
    jnz .Linvalid
    mov rax, [rdi+H_SLOTS]
    test rax, rax
    jz .Linvalid
    lea rcx, [rax-1]
    test rcx, rax
    jnz .Linvalid
    cmp [rdi+H_RECORDS], rax
    jae .Linvalid
    mov [rdx+V_HEADER], rdi
    lea rcx, [rdi+H_BYTES]
    sub rsi, H_BYTES
.macro section n, stride, dest
    mov [rdx+\dest], rcx
    mov rax, [rdi+\n]
    imul rax, rax, \stride
    jo .Linvalid
    test rax, rax
    js .Linvalid
    sub rsi, rax
    jb .Linvalid
    add rcx, rax
.endm
    cmp qword ptr [rdi+H_MODULES], 0
    je .Linvalid
    section H_MODULES, M_BYTES, V_MODULES
    section H_RECORDS, R_BYTES, V_RECORDS
    section H_SLOTS, 8, V_SLOTS
    cmp rsi, [rdi+H_POOL]
    jne .Linvalid
    mov [rdx+V_POOL], rcx
    xor eax, eax
    ret
.Linvalid:
    mov eax, -1
    ret
.size catalog_view, .-catalog_view

.globl catalog_find
.hidden catalog_find
.type catalog_find, @function
# (view,key,keylen) -> 1 and (rdx=archive path,rcx=path length,r8=kind,
# r9=archive fingerprint), 0 absent, -1 damaged selected data.
catalog_find:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rsi
    mov rsi, rdx
    call asm_zstd_xxh64
    mov rbx, rax
    mov rbp, [r12+V_HEADER]
    mov r10, [rbp+H_SLOTS]
    lea r11, [r10-1]
    mov r15, rbx
.Lprobe:
    and r15, r11
    mov rax, [r12+V_SLOTS]
    mov rax, [rax+r15*8]
    test rax, rax
    jz .Lmiss
    cmp rax, [rbp+H_RECORDS]
    ja .Lbad
    dec rax
    imul rax, R_BYTES
    add rax, [r12+V_RECORDS]
    cmp [rax+R_HASH], rbx
    jne .Lnext
    cmp [rax+R_LENGTH], r14
    jne .Lnext
    mov rcx, [rbp+H_POOL]
    mov rsi, [rax+R_KEY]
    sub rcx, rsi
    jb .Lbad
    cmp r14, rcx
    ja .Lbad
    add rsi, [r12+V_POOL]
    mov rdi, r13
    mov rcx, r14
    repe cmpsb
    jne .Lnext
    mov r8, [rax+R_KIND]
    cmp r8, 7
    ja .Lbad
    mov rax, [rax+R_MODULE]
    cmp rax, [rbp+H_MODULES]
    jae .Lbad
    shl rax, 4
    add rax, [r12+V_MODULES]
    mov r9, [rax+M_SIGNATURE]
    mov rdx, [rax+M_PATH]
    mov rcx, [rbp+H_POOL]
    sub rcx, rdx
    jbe .Lbad
    add rdx, [r12+V_POOL]
    cmp byte ptr [rdx], '/'
    jne .Lbad
    mov rdi, rdx
    xor eax, eax
    repne scasb
    jne .Lbad
    lea rcx, [rdi-1]
    sub rcx, rdx
    mov eax, 1
    jmp .Lret
.Lnext:
    inc r15
    dec r10
    jnz .Lprobe
.Lbad:
    mov eax, -1
    jmp .Lret
.Lmiss:
    xor eax, eax
.Lret:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size catalog_find, .-catalog_find
.section .note.GNU-stack,"",@progbits
