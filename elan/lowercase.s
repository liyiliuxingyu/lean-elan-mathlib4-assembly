/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Unicode default lowercase for Rust str::to_lowercase on command paths.
 * The only multi-scalar default mapping is U+0130. U+03A3 needs context. */
.intel_syntax noprefix
.text
/* rdi=destination cursor, rsi=original NUL text, rdx=bound.
 * rdi=new NUL cursor, CF reports capacity failure. */
.globl elan_lower_into
elan_lower_into:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov r12, rsi
    mov r13, rdi
    mov r14, rdx
    mov rdi, r12
    call elan_strlen
    mov r15, rax
    mov qword ptr [rsp], 0
    mov qword ptr [rsp+8], 0
    mov rdi, r12
    mov rsi, r15
    mov rdx, rsp
    lea rcx, [rsp+8]
    call _ZN4lean13validate_utf8EPKhmRmS2_
    test eax, eax
    jnz .Lstart
    /* A non-UTF-8 OsStr has no lowercase transformation. */
    mov rdi, r13
    mov rsi, r12
    mov rdx, r14
    call elan_append_z
    jmp .Lreturn
.Lstart:
    mov qword ptr [rsp], 0
    xor ebp, ebp                    /* preceding non-ignored character was cased */
.Lscalar:
    cmp [rsp], r15
    jae .Ldone
    mov rdi, r12
    mov rsi, r15
    mov rdx, rsp
    call _ZN4lean9next_utf8EPKcmRm
    mov ebx, eax
    cmp eax, 0x3a3
    jne .Lordinary
    test ebp, ebp
    jz .Lsigma
    mov rax, [rsp]
    mov [rsp+8], rax
.Llookahead:
    cmp [rsp+8], r15
    jae .Lfinal_sigma
    mov rdi, r12
    mov rsi, r15
    lea rdx, [rsp+8]
    call _ZN4lean9next_utf8EPKcmRm
    call .Lclass
    cmp eax, 2
    je .Llookahead
    test eax, eax
    jnz .Lsigma
.Lfinal_sigma:
    mov esi, 0x3c2
    jmp .Lsigma_context
.Lsigma:
    mov esi, 0x3c3
.Lsigma_context:
    mov ebp, 1
    jmp .Lemit
.Lordinary:
    call .Lclass
    cmp eax, 2
    cmovne ebp, eax
    cmp ebx, 0x130
    jne .Lmap
    lea rax, [r13+3]
    cmp rax, r14
    jae .Lfull
    mov byte ptr [r13], 'i'
    mov word ptr [r13+1], 0x87cc
    mov r13, rax
    jmp .Lscalar
.Lmap:
    mov eax, ebx
    lea r8, [rip+.Lmappings]
    mov r9d, OFFSET FLAT:MAPS
    call .Lrange
    mov esi, ebx
    test rdx, rdx
    jz .Lemit
    sub eax, [rdx]
    test eax, [rdx+12]              /* low bit for alternate-source ranges */
    jnz .Lemit
    add esi, [rdx+8]
.Lemit:
    lea rdi, [rsp+16]
    call _ZN4lean19push_unicode_scalarEPcj
    lea rcx, [r13+rax]
    cmp rcx, r14
    jae .Lfull
    mov rdi, r13
    mov r13, rcx
    mov ecx, eax
    lea rsi, [rsp+16]
    rep movsb
    jmp .Lscalar
.Ldone:
    cmp r13, r14
    jae .Lfull
    mov byte ptr [r13], 0
    mov rdi, r13
    clc
    jmp .Lreturn
.Lfull:
    stc
.Lreturn:
    lea rsp, [rsp+40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
/* Class: 0 neither, 1 Cased, 2 Case_Ignorable (takes precedence). */
.Lclass:
    lea r8, [rip+.Lcontext]
    mov r9d, OFFSET FLAT:CONTEXTS
    call .Lrange
    xor eax, eax
    test rdx, rdx
    jz .Lclass_return
    mov eax, [rdx+8]
.Lclass_return:
    ret
/* Binary-search inclusive [first,last] records, leaving scalar EAX intact. */
.Lrange:
    xor ecx, ecx
.Lsearch:
    cmp ecx, r9d
    jae .Lnone
    lea esi, [rcx+r9]
    shr esi, 1
    mov edx, esi
    shl edx, 4
    add rdx, r8
    cmp eax, [rdx]
    jb .Lleft
    cmp eax, [rdx+4]
    jbe .Lfound
    lea ecx, [rsi+1]
    jmp .Lsearch
.Lleft:
    mov r9d, esi
    jmp .Lsearch
.Lnone:
    xor edx, edx
.Lfound:
    ret
.include "lowercase_data.inc"
.section .note.GNU-stack,"",@progbits
