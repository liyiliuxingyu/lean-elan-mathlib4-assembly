# SPDX-License-Identifier: Apache-2.0
# RFC 8878, sections 3.1.1.3, 3.1.1.4 and 5. Entropy tables and history
# persist across blocks of one frame. Offsets below are private to this file.
.intel_syntax noprefix
.equ LL, 16384
.equ OF, 20480
.equ ML, 24576
.equ REP1, 28672
.equ REP2, 28680
.equ REP3, 28688
.equ DICTEND, 28696
.equ DICTLEN, 28704
.equ WINDOW, 28712

.text
.global z6_entropy_init
.type z6_entropy_init, @function
z6_entropy_init:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    lea r14, [rsi+rdx]
    mov [r12+WINDOW], rcx
    mov qword ptr [r12], 0
    mov dword ptr [r12+LL], -1
    mov dword ptr [r12+OF], -1
    mov dword ptr [r12+ML], -1
    mov qword ptr [r12+REP1], 1
    mov qword ptr [r12+REP2], 4
    mov qword ptr [r12+REP3], 8
    cmp rdx, 4
    jb .Lhistory
    cmp dword ptr [r13], 0xec30a437
    jne .Lhistory
    cmp rdx, 8
    jb .Linit_err
    cmp dword ptr [r13+4], 0          # formal dictionary IDs are nonzero
    je .Linit_err
    add r13, 8
    mov rsi, r13
    sub rdx, 8
    call zstd_huff_tree
    test rax, rax
    jle .Linit_err
    add r13, rax
.macro dict_table field, maxsym, maxlog
    mov rdi, r13
    mov rsi, r14
    sub rsi, r13
    mov edx, \maxsym
    mov ecx, \maxlog
    lea r8, [r12+\field]
    call z6_fse_read
    test rax, rax
    jle .Linit_err
    add r13, rax
.endm
    dict_table OF, 31, 8
    dict_table ML, 52, 9
    dict_table LL, 35, 9
    mov rcx, r14
    sub rcx, r13
    sub rcx, 12
    jb .Linit_err
    .irp slot, 0, 1, 2
    mov eax, [r13+4*\slot]
    test eax, eax
    jz .Linit_err
    cmp rax, rcx
    ja .Linit_err
    mov [r12+REP1+8*\slot], rax
    .endr
    add r13, 12
.Lhistory:
    mov [r12+DICTEND], r14
    sub r14, r13
    mov [r12+DICTLEN], r14
    xor eax, eax
    jmp .Linit_ret
.Linit_err:
    mov rax, -1
.Linit_ret:
    pop r14
    pop r13
    pop r12
    ret
.size z6_entropy_init, .-z6_entropy_init

.section .rodata
# Normalized distributions and length codes specified by RFC 8878.
.align 2
.Lll_norm:
    .short 4,3,2,2,2,2,2,2,2,2,2,2,2,1,1,1,2,2,2,2,2,2,2,2,2,3,2,1,1,1,1,1,-1,-1,-1,-1
.Lof_norm:
    .short 1,1,1,1,1,1,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1
.Lml_norm:
    .short 1,4,3,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,-1,-1,-1,-1,-1,-1,-1
.Lll_bits:
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,2,3,3,4,6,7,8,9,10,11,12,13,14,15,16
.Lml_bits:
    .rept 32
    .byte 0
    .endr
    .byte 1,1,1,1,2,2,3,3,4,4,5,7,8,9,10,11,12,13,14,15,16
.align 4
.Lll_base:
    .long 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,20,22,24,28,32,40,48,64,128,256,512,1024,2048,4096,8192,16384,32768,65536
.Lml_base:
    .long 3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34
    .long 35,37,39,41,43,47,51,59,67,83,99,131,259,515,1027,2051,4099,8195,16387,32771,65539

.text
# Local bit reader. r13 = beginning, r14 = end, r15 = remaining bits.
# Inputs ecx = 0..31. All loads stay within the bitstream, even at EOF.
.Lreverse:
    xor eax, eax
    test ecx, ecx
    jz .Lrevret
    sub r15, rcx
    jb .Lrevbad
    mov r8, r15
    shr r8, 3
    add r8, r13
    lea r10, [r8+8]
    cmp r10, r14
    ja .Lshortbits
    mov rax, [r8]
    jmp .Lunpack
.Lshortbits:
    mov r10, r14
.Lonebyte:
    dec r10
    shl rax, 8
    mov al, [r10]
    cmp r10, r8
    ja .Lonebyte
.Lunpack:
    mov edx, 1
    shl edx, cl
    dec edx
    mov ecx, r15d
    and ecx, 7
    shr rax, cl
    and eax, edx
.Lrevret:
    ret
.Lrevbad:
    mov rax, -1
    ret

# Stack layout of one compressed block's execution.
.equ LITPTR, 0
.equ LITLEFT, 8
.equ OUTBASE, 16
.equ PRIOR, 24
.equ TOTAL, 32
.equ LIMIT, 40
.equ NSEQ, 48
.equ MODES, 52
.equ ST_LL, 56
.equ ST_OF, 60
.equ ST_ML, 64
.equ ENTRY_LL, 68
.equ ENTRY_OF, 72
.equ ENTRY_ML, 76
.equ DIST, 80
.equ MATCHLEN, 88
.equ LITLEN, 96
.equ S_BYTES, 104

.global z6_sequences
.type z6_sequences, @function
z6_sequences:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, S_BYTES
    mov r12, rdi
    mov r13, rsi
    lea r14, [rsi+rdx]
    mov [rsp+LITPTR], rcx
    mov [rsp+LITLEFT], r8
    mov [rsp+OUTBASE], r9
    mov rax, [rbp+16]
    mov [rsp+PRIOR], rax
    mov [rsp+TOTAL], rax
    mov rcx, [rbp+24]
    mov [rsp+LIMIT], rcx
    cmp rax, rcx
    ja .Lcap
    test rdx, rdx
    jz .Lbad
    movzx eax, byte ptr [r13]
    inc r13
    test eax, eax
    jnz .Lcountmore
    cmp r13, r14
    jne .Lbad
    jmp .Ltrailing
.Lcountmore:
    cmp eax, 128
    jb .Lcounted
    cmp r13, r14
    jae .Lbad
    cmp eax, 255
    je .Llongcount
    sub eax, 128
    shl eax, 8
    mov al, [r13]
    inc r13
    test eax, eax
    jz .Lbad
    jmp .Lcounted
.Llongcount:
    lea rax, [r13+2]
    cmp rax, r14
    ja .Lbad
    movzx eax, word ptr [r13]
    add eax, 0x7f00
    add r13, 2
.Lcounted:
    mov [rsp+NSEQ], eax
    cmp r13, r14
    jae .Lbad
    movzx eax, byte ptr [r13]
    inc r13
    test al, 3
    jnz .Lbad
    mov [rsp+MODES], eax
.macro load_table field, shift, norm, count, log, maxsym, maxlog
    mov eax, [rsp+MODES]
    shr eax, \shift
    and eax, 3
    cmp eax, 2
    je .Lfse\@
    ja .Lreuse\@
    test eax, eax
    jnz .Lrle\@
    lea rdi, [rip+\norm]
    mov esi, \count
    mov edx, \log
    lea rcx, [r12+\field]
    call z6_fse_build
    test eax, eax
    jnz .Lbad
    jmp .Ltableok\@
.Lrle\@:
    cmp r13, r14
    jae .Lbad
    movzx eax, byte ptr [r13]
    inc r13
    cmp eax, \maxsym
    ja .Lbad
    mov qword ptr [r12+\field], 0
    mov [r12+\field+7], al
    jmp .Ltableok\@
.Lfse\@:
    mov rdi, r13
    mov rsi, r14
    sub rsi, r13
    mov edx, \maxsym
    mov ecx, \maxlog
    lea r8, [r12+\field]
    call z6_fse_read
    test rax, rax
    jle .Lbad
    add r13, rax
    jmp .Ltableok\@
.Lreuse\@:
    cmp dword ptr [r12+\field], -1
    je .Lbad
.Ltableok\@:
.endm
    load_table LL, 6, .Lll_norm, 36, 6, 35, 9
    load_table OF, 4, .Lof_norm, 29, 5, 31, 8
    load_table ML, 2, .Lml_norm, 53, 6, 52, 9
    cmp r13, r14
    jae .Lbad
    movzx eax, byte ptr [r14-1]
    bsr eax, eax
    jz .Lbad
    mov r15, r14
    sub r15, r13
    dec r15
    lea r15, [rax+r15*8]
.macro initial field, state
    mov ecx, [r12+\field]
    call .Lreverse
    test rax, rax
    js .Lbad
    mov [rsp+\state], eax
.endm
    initial LL, ST_LL
    initial OF, ST_OF
    initial ML, ST_ML
.Lsequence:
.macro get_entry field, state, entry
    mov eax, [rsp+\state]
    mov eax, [r12+\field+4+rax*4]
    mov [rsp+\entry], eax
.endm
    get_entry LL, ST_LL, ENTRY_LL
    get_entry ML, ST_ML, ENTRY_ML
    get_entry OF, ST_OF, ENTRY_OF
    shr eax, 24
    mov ebx, 1
    mov ecx, eax
    shl ebx, cl
    call .Lreverse
    test rax, rax
    js .Lbad
    add rax, rbx
    mov [rsp+DIST], rax
.macro get_length entry, base, bits, dest
    mov ebx, [rsp+\entry]
    shr ebx, 24
    lea rax, [rip+\bits]
    movzx ecx, byte ptr [rax+rbx]
    call .Lreverse
    test rax, rax
    js .Lbad
    lea rdx, [rip+\base]
    mov edx, [rdx+rbx*4]
    add rax, rdx
    mov [rsp+\dest], rax
.endm
    get_length ENTRY_ML, .Lml_base, .Lml_bits, MATCHLEN
    get_length ENTRY_LL, .Lll_base, .Lll_bits, LITLEN
    mov rax, [rsp+DIST]
    cmp rax, 3
    jbe .Lrepeat
    sub rax, 3
    jmp .Lrotate3
.Lrepeat:
    cmp qword ptr [rsp+LITLEN], 0
    jne .Lselect
    inc eax
.Lselect:
    cmp eax, 2
    jb .Lrep1
    je .Lrep2
    cmp eax, 3
    je .Lrep3
    mov rax, [r12+REP1]
    dec rax
    jz .Lbad
    jmp .Lrotate3
.Lrep1:
    mov rax, [r12+REP1]
    jmp .Lsaveoffset
.Lrep2:
    mov rax, [r12+REP2]
    jmp .Lrotate2
.Lrep3:
    mov rax, [r12+REP3]
.Lrotate3:
    mov rcx, [r12+REP2]
    mov [r12+REP3], rcx
.Lrotate2:
    mov rcx, [r12+REP1]
    mov [r12+REP2], rcx
    mov [r12+REP1], rax
.Lsaveoffset:
    mov [rsp+DIST], rax
    dec dword ptr [rsp+NSEQ]
    jz .Lcopy
.macro next_state entry, state
    movzx ecx, byte ptr [rsp+\entry+2]
    call .Lreverse
    test rax, rax
    js .Lbad
    movzx edx, word ptr [rsp+\entry]
    add eax, edx
    mov [rsp+\state], eax
.endm
    next_state ENTRY_LL, ST_LL
    next_state ENTRY_ML, ST_ML
    next_state ENTRY_OF, ST_OF
.Lcopy:
    mov rcx, [rsp+LITLEN]
    cmp rcx, [rsp+LITLEFT]
    ja .Lbad
    mov rbx, [rsp+TOTAL]
    mov rax, [rsp+LIMIT]
    sub rax, rbx
    sub rax, rcx
    jb .Lcap
    cmp [rsp+MATCHLEN], rax
    ja .Lcap
    mov rdi, [rsp+OUTBASE]
    add rdi, rbx
    add rbx, rcx
    sub [rsp+LITLEFT], rcx
    mov rsi, [rsp+LITPTR]
    rep movsb
    mov [rsp+LITPTR], rsi
    mov rdx, [rsp+DIST]
    mov rcx, [rsp+MATCHLEN]
    mov rax, [r12+WINDOW]
    cmp rbx, rdx
    jb .Lfromdict
    cmp rdx, rax
    ja .Lbad
    jmp .Lfromoutput
.Lfromdict:
    # Before the window fills, the dictionary immediately precedes byte 0.
    cmp rbx, rax
    ja .Lbad
    mov r8, rdx
    sub r8, rbx
    cmp r8, [r12+DICTLEN]
    ja .Lbad
    mov rsi, [r12+DICTEND]
    sub rsi, r8
    mov r9, rcx
    cmp rcx, r8
    cmova rcx, r8
    sub r9, rcx
    rep movsb
    mov rcx, r9
.Lfromoutput:
    mov rsi, rdi
    sub rsi, rdx
    rep movsb                       # forward copy permits self-overlap
    add rbx, [rsp+MATCHLEN]
    mov [rsp+TOTAL], rbx
    cmp dword ptr [rsp+NSEQ], 0
    jne .Lsequence
    test r15, r15
    jnz .Lbad
.Ltrailing:
    mov rax, [rsp+TOTAL]
    mov rcx, [rsp+LITLEFT]
    mov rdx, [rsp+LIMIT]
    sub rdx, rax
    cmp rcx, rdx
    ja .Lcap
    mov rdi, [rsp+OUTBASE]
    add rdi, rax
    mov rsi, [rsp+LITPTR]
    add rax, rcx
    rep movsb
    sub rax, [rsp+PRIOR]
    jmp .Lseqret
.Lcap:
    mov rax, -2
    jmp .Lseqret
.Lbad:
    mov rax, -1
.Lseqret:
    add rsp, S_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size z6_sequences, .-z6_sequences
.section .note.GNU-stack, "", @progbits
