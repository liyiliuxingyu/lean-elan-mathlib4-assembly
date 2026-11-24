# SPDX-License-Identifier: Apache-2.0
# Optional test executable. Only this oracle links libc/libzstd (>= 1.4).
# argv: one raw frame, optionally its dictionary. Nonzero = failure.
.intel_syntax noprefix
.include "zstd.inc"
.section .rodata
.Lmode: .asciz "rb"
.text
# rdi = path, rax = buffer or NULL, rdx = byte size
.Lload:
    push rbx
    push r12
    push r13
    lea rsi, [rip+.Lmode]
    call fopen@PLT
    test rax, rax
    jz .Lload_return
    mov rbx, rax
    mov rdi, rax
    xor esi, esi
    mov edx, 2
    call fseek@PLT
    test eax, eax
    jnz .Lfile_error
    mov rdi, rbx
    call ftell@PLT
    test rax, rax
    jle .Lfile_error
    mov r12, rax
    mov rdi, rbx
    call rewind@PLT
    mov rdi, r12
    call malloc@PLT
    test rax, rax
    jz .Lfile_error
    mov r13, rax
    mov rdi, rax
    mov esi, 1
    mov rdx, r12
    mov rcx, rbx
    call fread@PLT
    cmp rax, r12
    jne .Lfile_error
    mov rdi, rbx
    call fclose@PLT
    mov rax, r13
    mov rdx, r12
    jmp .Lload_return
.Lfile_error:
    mov rdi, rbx
    call fclose@PLT
    xor eax, eax
.Lload_return:
    pop r13
    pop r12
    pop rbx
    ret

.equ O_HEADER, 80                     # struct ZSTD_frameHeader (48 bytes)
.equ O_PTR, 128
.equ O_SIZE, 136
.equ O_REFERENCE, 144
.equ O_ARGV, 152
.globl main
.type main,@function
main:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 168
    mov [rsp+O_ARGV], rsi
    mov ebp, edi
    cmp ebp, 2
    jb .Lio_error
    cmp ebp, 3
    ja .Lio_error
    mov rdi, [rsi+8]
    call .Lload
    test rax, rax
    jz .Lio_error
    mov r12, rax
    mov r13, rdx
    xor r14d, r14d
    xor r15d, r15d
    cmp ebp, 3
    jne .Loracle_frame
    mov rdi, [rsp+O_ARGV]
    mov rdi, [rdi+16]
    call .Lload
    test rax, rax
    jz .Lio_error
    mov r14, rax
    mov r15, rdx
.Loracle_frame:
    mov ebp, 2
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call asm_zstd_inspect
    test eax, eax
    jnz .Lfinish
    mov rdi, r12
    mov rsi, r13
    call ZSTD_findFrameCompressedSize@PLT
    cmp rax, r13
    jne .Lfinish
    cmp rax, [rsp+ZSTD_CONSUMED]
    jne .Lfinish
    lea rdi, [rsp+O_HEADER]
    mov rsi, r12
    mov rdx, r13
    call ZSTD_getFrameHeader@PLT
    test rax, rax
    jnz .Lfinish
    mov rax, [rsp+O_HEADER]            # frameContentSize
    cmp rax, [rsp+ZSTD_CONTENT_SIZE]
    jne .Lfinish
    mov rax, [rsp+O_HEADER+8]          # windowSize
    cmp rax, [rsp+ZSTD_WINDOW]
    jne .Lfinish
    mov eax, [rsp+O_HEADER+24]         # headerSize
    cmp rax, [rsp+ZSTD_HEADER_BYTES]
    jne .Lfinish
    mov eax, [rsp+O_HEADER+28]         # dictID
    cmp rax, [rsp+ZSTD_DICT_ID]
    jne .Lfinish
    mov eax, [rsp+ZSTD_FLAGS]
    shr eax, 1
    and eax, 1
    cmp eax, [rsp+O_HEADER+32]         # checksumFlag
    jne .Lfinish
    mov ebp, 3
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov rcx, r15
    lea r8, [rsp+O_PTR]
    lea r9, [rsp+O_SIZE]
    call asm_zstd_decode_dict_alloc
    test eax, eax
    jnz .Lfinish
    mov ebp, 4
    mov rdi, [rsp+O_SIZE]
    mov eax, 1
    test rdi, rdi
    cmovz rdi, rax
    call malloc@PLT
    test rax, rax
    jz .Lfinish
    mov [rsp+O_REFERENCE], rax
    call ZSTD_createDCtx@PLT
    test rax, rax
    jz .Lfinish
    mov rdi, rax
    mov rsi, [rsp+O_REFERENCE]
    mov rdx, [rsp+O_SIZE]
    mov rcx, r12
    mov r8, r13
    mov r9, r14
    sub rsp, 8
    push r15
    call ZSTD_decompress_usingDict@PLT
    add rsp, 16
    cmp rax, [rsp+O_SIZE]
    jne .Lfinish
    mov ebp, 5
    mov rdi, [rsp+O_PTR]
    mov rsi, [rsp+O_REFERENCE]
    mov rdx, rax
    call memcmp@PLT
    test eax, eax
    jnz .Lfinish
    xor ebp, ebp
    jmp .Lfinish
.Lio_error:
    mov ebp, 1
.Lfinish:
    mov eax, ebp
    add rsp, 168
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size main,.-main
.section .note.GNU-stack,"",@progbits
