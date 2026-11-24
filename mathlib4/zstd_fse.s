# SPDX-License-Identifier: Apache-2.0
/* RFC 8878, normalized probability and finite-state decoding tables.
   Entries after the 4-byte accuracy log are {u16 base, u8 bits, u8 sym}. */
.intel_syntax noprefix
.text
/* Stack-free forward bit read. r12=source, r13=size, r14=bit offset,
   ecx=width (0..10). Returns eax=value or -1; advances the bit offset. */
.Lforward:
    lea rdx, [r14+rcx]
    lea r8, [rdx+7]
    shr r8, 3
    cmp r8, r13
    ja .Lferr
    mov r9, r14
    shr r9, 3
    lea r8, [r9+4]
    cmp r8, r13
    ja .Lfshort
    mov eax, [r12+r9]
    jmp .Lfvalue
.Lfshort:
    # Assemble the last 0..3 bytes without reading outside the input.
    mov r8, r13
    xor eax, eax
.Lfbyte:
    cmp r8, r9
    jbe .Lfvalue
    dec r8
    shl eax, 8
    mov al, [r12+r8]
    jmp .Lfbyte
.Lfvalue:
    mov r8d, 1
    shl r8d, cl
    dec r8d
    mov ecx, r14d
    and ecx, 7
    shr eax, cl
    and eax, r8d
    mov r14, rdx
    ret
.Lferr:
    mov eax, -1
    ret

.global z6_fse_read
.type z6_fse_read, @function
z6_fse_read:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 568
    /* norm[256] starts at rsp. The saved parameters and counts follow it. */
    mov r12, rdi
    mov r13, rsi
    mov [rsp+512], r8
    mov [rsp+520], edx
    mov [rsp+524], ecx
    cmp edx, 255
    ja .Lreaderr
    cmp ecx, 9
    ja .Lreaderr
    mov rdi, rsp
    xor eax, eax
    mov ecx, 64
    rep stosq
    xor r14d, r14d
    mov ecx, 4
    call .Lforward
    test eax, eax
    js .Lreaderr
    add eax, 5
    cmp eax, [rsp+524]
    ja .Lreaderr
    mov [rsp+528], eax
    mov ecx, eax
    mov ebx, 1
    shl ebx, cl
    inc ebx                         /* remaining mass + 1 */
    xor r15d, r15d                   /* next symbol */
.Lprob:
    cmp ebx, 1
    je .Lbuildread
    cmp r15d, [rsp+520]
    ja .Lreaderr
    bsr ecx, ebx
    /* For the initial remaining=tableSize+1 and all later values,
       threshold is highest power of two <=remaining. */
    mov eax, 1
    shl eax, cl
    mov [rsp+532], eax
    lea eax, [rax+rax-1]
    sub eax, ebx
    mov [rsp+536], eax
    call .Lforward
    test eax, eax
    js .Lreaderr
    cmp eax, [rsp+536]
    jb .Lcount
    mov [rsp+540], eax
    mov ecx, 1
    call .Lforward
    test eax, eax
    js .Lreaderr
    imul eax, [rsp+532]
    add eax, [rsp+540]
    cmp eax, [rsp+532]
    jb .Lcount
    sub eax, [rsp+536]
.Lcount:
    dec eax
    mov [rsp+r15*2], ax
    inc r15d
    test eax, eax
    jz .Lzeroes
    mov edx, eax
    sar edx, 31
    xor eax, edx
    sub eax, edx
    sub ebx, eax
    cmp ebx, 1
    jl .Lreaderr
    jmp .Lprob
.Lzeroes:
    mov ecx, 2
    call .Lforward
    test eax, eax
    js .Lreaderr
    add r15d, eax
    cmp r15d, [rsp+520]
    ja .Lreaderr
    cmp eax, 3
    je .Lzeroes
    jmp .Lprob
.Lbuildread:
    mov rdi, rsp
    mov esi, r15d
    mov edx, [rsp+528]
    mov rcx, [rsp+512]
    call z6_fse_build
    test eax, eax
    jnz .Lreaderr
    lea rax, [r14+7]
    shr rax, 3
    jmp .Lreadout
.Lreaderr:
    mov rax, -1
.Lreadout:
    add rsp, 568
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size z6_fse_read, .-z6_fse_read

/* rdi=i16 probabilities, esi=symbol count, edx=accuracy log, rcx=table. */
.global z6_fse_build
.type z6_fse_build, @function
z6_fse_build:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 512
    cmp esi, 256
    ja .Lbuilderr
    cmp edx, 5
    jb .Lbuilderr
    cmp edx, 9
    ja .Lbuilderr
    mov r12, rcx
    mov [r12], edx
    mov ecx, edx
    mov r13d, 1
    shl r13d, cl                     /* size */
    lea r14d, [r13-1]                /* highest unreserved slot */
    xor r8d, r8d
    xor r9d, r9d
.Lreserve:
    cmp r8d, esi
    jae .Lreserved
    movsx eax, word ptr [rdi+r8*2]
    cmp eax, -1
    jl .Lbuilderr
    jne .Lrecord
    test r14d, r14d
    js .Lbuilderr
    mov [r12+r14*4+7], r8b
    dec r14d
    mov eax, 1
.Lrecord:
    mov [rsp+r8*2], ax
    add r9d, eax
    inc r8d
    jmp .Lreserve
.Lreserved:
    cmp r9d, r13d
    jne .Lbuilderr
    mov eax, r13d
    shr eax, 1
    mov ebx, r13d
    shr ebx, 3
    lea ebx, [rbx+rax+3]              /* permutation stride */
    lea r15d, [r13-1]
    xor r8d, r8d
    xor r9d, r9d
.Lsymbol:
    cmp r8d, esi
    jae .Lstates
    movsx ecx, word ptr [rdi+r8*2]
    test ecx, ecx
    jle .Lnextsym
.Lspread:
    mov [r12+r9*4+7], r8b
.Ladvance:
    add r9d, ebx
    and r9d, r15d
    cmp r9d, r14d
    jg .Ladvance
    dec ecx
    jnz .Lspread
.Lnextsym:
    inc r8d
    jmp .Lsymbol
.Lstates:
    test r9d, r9d
    jnz .Lbuilderr
.Lstate:
    movzx eax, byte ptr [r12+r9*4+7]
    movzx ebx, word ptr [rsp+rax*2]
    inc word ptr [rsp+rax*2]
    bsr eax, ebx
    jz .Lbuilderr
    mov ecx, edx
    sub ecx, eax
    mov [r12+r9*4+6], cl
    shl ebx, cl
    sub ebx, r13d
    mov [r12+r9*4+4], bx
    inc r9d
    cmp r9d, r13d
    jb .Lstate
    xor eax, eax
    jmp .Lbuildout
.Lbuilderr:
    mov rax, -1
.Lbuildout:
    add rsp, 512
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size z6_fse_build, .-z6_fse_build
.section .note.GNU-stack, "", @progbits
