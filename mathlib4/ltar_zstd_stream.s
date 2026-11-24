# SPDX-License-Identifier: Apache-2.0
# Decode the sequence of Zstandard frames making up one leantar member.
.intel_syntax noprefix
.include "zstd.inc"

.equ FRAME_DATA, ZSTD_INFO_BYTES
.equ FRAME_SIZE, FRAME_DATA+8
.equ OUT_ADDRESS, FRAME_SIZE+8
.equ OUT_SIZE, OUT_ADDRESS+8
.equ STREAM_LOCALS, OUT_SIZE+16

.text
.globl mathlib_ltar_zstd_stream
.type mathlib_ltar_zstd_stream,@function
# (src, size, dictionary, dictionary_size, &output, &size) -> zero or error.
# On success the caller owns an mmap of max(1, size). Decoding to private
# mappings ensures a damaged later frame cannot publish a partial member.
mathlib_ltar_zstd_stream:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, STREAM_LOCALS
    mov [rsp+OUT_ADDRESS], r8
    mov [rsp+OUT_SIZE], r9
    mov qword ptr [r8], 0
    mov qword ptr [r9], 0
    mov r12, rdi                       # cursor
    mov r13, rdi                       # end
    mov r14, rdx                       # dictionary is reset for each frame
    mov r15, rcx
    xor ebx, ebx                       # owned output mapping
    xor ebp, ebp                       # assembled byte length
    add r13, rsi
    jc .Linvalid
    test rsi, rsi
    jz .Linvalid                       # an empty stream is a truncated frame
.Lframe:
    mov rsi, r13
    sub rsi, r12
    jz .Lcomplete
    cmp rsi, 4
    jb .Linvalid
    mov eax, [r12]
    and eax, -16
    cmp eax, 0x184d2a50                 # sixteen skippable magic values
    je .Lskip

    mov rdi, r12
    mov rdx, rsp
    call asm_zstd_inspect
    test eax, eax
    jnz .Lfail
    mov rdi, r12
    mov rsi, [rsp+ZSTD_CONSUMED]
    add r12, rsi
    mov rdx, r14
    mov rcx, r15
    lea r8, [rsp+FRAME_DATA]
    lea r9, [rsp+FRAME_SIZE]
    call asm_zstd_decode_dict_alloc
    test eax, eax
    jnz .Lfail
    test rbx, rbx
    jnz .Lappend
    # Transfer ownership. The usual one-frame archive never copies its data.
    mov rbx, [rsp+FRAME_DATA]
    mov rbp, [rsp+FRAME_SIZE]
    jmp .Lframe

.Lskip:
    sub rsi, 8
    jb .Linvalid
    mov eax, [r12+4]
    cmp rax, rsi
    ja .Linvalid
    lea r12, [r12+rax+8]
    jmp .Lframe

.Lappend:
    mov rcx, [rsp+FRAME_SIZE]
    test rcx, rcx
    jz .Ldiscard_fragment
    mov rdx, rbp
    add rdx, rcx
    jc .Lappend_error
    # Extend the aggregate in place or remap it. mremap operates on whole
    # pages, so small fragments within the current last page need no syscall.
    mov esi, 1
    test rbp, rbp
    cmovnz rsi, rbp
    lea rax, [rsi-1]
    lea rdi, [rdx-1]
    xor rax, rdi
    shr rax, 12
    jz .Lcopy
    mov rdi, rbx
    mov r10d, 1                         # MREMAP_MAYMOVE
    mov eax, 25
    syscall
    cmp rax, -4095
    jae .Lappend_error
    mov rbx, rax
.Lcopy:
    lea rdi, [rbx+rbp]
    mov rcx, [rsp+FRAME_SIZE]
    mov rsi, [rsp+FRAME_DATA]
    add rbp, rcx
    rep movsb
.Ldiscard_fragment:
    call .Lfree_fragment
    jmp .Lframe
.Lappend_error:
    call .Lfree_fragment
    mov eax, ZSTD_ALLOC
    jmp .Lfail
.Lfree_fragment:
    mov rdi, [rsp+FRAME_DATA+8]         # account for local return address
    mov rsi, [rsp+FRAME_SIZE+8]
    test rsi, rsi
    jnz .Lunmap_fragment
    inc esi
.Lunmap_fragment:
    mov eax, 11
    syscall
    ret

.Lcomplete:
    test rbx, rbx
    jnz .Lpublish
    # A stream of complete skippable frames decompresses to an empty member.
    xor edi, edi
    mov esi, 1
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    cmp rax, -4095
    jae .Lalloc_error
    mov rbx, rax
.Lpublish:
    mov rdx, [rsp+OUT_ADDRESS]
    mov [rdx], rbx
    mov rdx, [rsp+OUT_SIZE]
    mov [rdx], rbp
    xor eax, eax
    jmp .Lreturn
.Lalloc_error:
    mov eax, ZSTD_ALLOC
    jmp .Lreturn
.Linvalid:
    mov eax, ZSTD_INVALID
.Lfail:
    test rbx, rbx
    jz .Lreturn
    mov r12d, eax
    mov rdi, rbx
    mov esi, 1
    test rbp, rbp
    cmovnz rsi, rbp
    mov eax, 11
    syscall
    mov eax, r12d
.Lreturn:
    add rsp, STREAM_LOCALS
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size mathlib_ltar_zstd_stream,.-mathlib_ltar_zstd_stream
.section .note.GNU-stack,"",@progbits
