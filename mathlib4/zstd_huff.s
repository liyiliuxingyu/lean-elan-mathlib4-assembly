# SPDX-License-Identifier: Apache-2.0
# Zstandard Huffman trees and literal sections (RFC 8878, sections 3 and 4).
.intel_syntax noprefix
.text

.equ RANKS, 256                 # weights[256], rank starts/counts[12], FSE table
.equ FSE, 304
.equ TREE_FRAME, 568

# ssize_t zstd_huff_tree(ctx, src, size). ctx holds a qword tableLog followed
# by 2048 two-byte entries {bit count, symbol}. Returns encoded bytes consumed.
.globl zstd_huff_tree
.type zstd_huff_tree,@function
zstd_huff_tree:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, TREE_FRAME
    test rdx, rdx
    jz .Ltree_error
    mov r12, rdi
    lea r13, [rsi + 1]
    dec rdx
    movzx ebx, byte ptr [rsi]
    cmp ebx, 128
    jb .Lentropy_weights

    lea r15d, [rbx - 127]       # number of explicit weights
    lea r14d, [r15 + 1]
    shr r14d, 1
    cmp r14, rdx
    ja .Ltree_error
    xor ecx, ecx
.Lunpack_weights:
    movzx eax, byte ptr [r13 + rcx]
    mov edx, eax
    shr eax, 4
    and edx, 15
    mov [rsp + rcx*2], al
    mov [rsp + rcx*2 + 1], dl
    inc ecx
    cmp ecx, r14d
    jb .Lunpack_weights
    inc r14d
    jmp .Lbuild_tree

.Lentropy_weights:
    test ebx, ebx
    jz .Ltree_error
    cmp rbx, rdx
    ja .Ltree_error
    mov rdi, r13
    mov esi, ebx
    mov edx, 255
    mov ecx, 6
    lea r8, [rsp + FSE]
    call z6_fse_read
    cmp rax, rbx                 # reserve at least the stream end marker
    jae .Ltree_error
    lea r14d, [rbx + 1]
    lea rdi, [r13 + rax]         # first byte of the reverse bitstream
    movzx edx, byte ptr [r13 + rbx - 1]
    test edx, edx
    jz .Ltree_error
    bsr edx, edx
    sub rbx, rax
    lea rsi, [rdx + rbx*8 - 8]   # number of available bits before the marker
    mov ecx, [rsp + FSE]
    lea eax, [rcx + rcx]
    cmp esi, eax
    jb .Ltree_error
    call .Lweight_bits
    mov r8d, eax                 # two alternate FSE states
    mov ecx, [rsp + FSE]
    call .Lweight_bits
    mov r9d, eax
    xor r15d, r15d
.Lnext_weight:
    cmp r15d, 255
    jae .Ltree_error
    mov r10d, [rsp + FSE + 4 + r8*4]
    mov eax, r10d
    shr eax, 24
    mov [rsp + r15], al
    inc r15d
    mov ecx, r10d
    shr ecx, 16
    and ecx, 255
    cmp esi, ecx
    jb .Lfinal_weight
    call .Lweight_bits
    movzx edx, r10w
    add eax, edx
    mov r8d, r9d
    mov r9d, eax
    jmp .Lnext_weight
.Lfinal_weight:
    cmp r15d, 255
    jae .Ltree_error
    mov al, [rsp + FSE + 7 + r9*4]
    mov [rsp + r15], al
    inc r15d

.Lbuild_tree:
    lea rdi, [rsp + RANKS]
    xor eax, eax
    mov ecx, 12
    rep stosd
    xor ebp, ebp                 # sum of slots used by explicit symbols
    xor ebx, ebx
.Lcount_weight:
    movzx ecx, byte ptr [rsp + rbx]
    cmp ecx, 11
    ja .Ltree_error
    test ecx, ecx
    jz .Lskip_weight
    inc dword ptr [rsp + RANKS + rcx*4]
    dec ecx
    mov eax, 1
    shl eax, cl
    add ebp, eax
.Lskip_weight:
    inc ebx
    cmp ebx, r15d
    jb .Lcount_weight
    test ebp, ebp
    jz .Ltree_error
    bsr ebx, ebp
    inc ebx                     # ceil(log2(sum + 1))
    cmp ebx, 11
    ja .Ltree_error
    mov ecx, ebx
    mov eax, 1
    shl eax, cl
    sub eax, ebp                # remaining slots must form one symbol
    lea edx, [rax - 1]
    test edx, eax
    jnz .Ltree_error
    bsr ecx, eax
    inc ecx
    mov [rsp + r15], cl
    inc r15d
    inc dword ptr [rsp + RANKS + rcx*4]
    mov eax, [rsp + RANKS + 4]
    cmp eax, 2
    jb .Ltree_error
    test al, 1
    jnz .Ltree_error

    xor ecx, ecx
    xor eax, eax
.Lrank_start:
    mov edx, [rsp + RANKS + 4 + rcx*4]
    mov [rsp + RANKS + 4 + rcx*4], eax
    shl edx, cl
    add eax, edx
    inc ecx
    cmp ecx, ebx
    jb .Lrank_start

    xor ebp, ebp                 # symbol number
.Lplace_symbol:
    movzx r8d, byte ptr [rsp + rbp]
    test r8d, r8d
    jz .Lnext_symbol
    lea ecx, [r8 - 1]
    mov edx, 1
    shl edx, cl                  # copies in the full lookup table
    mov edi, [rsp + RANKS + r8*4]
    add [rsp + RANKS + r8*4], edx
    lea rdi, [r12 + rdi*2 + 8]
    mov eax, ebp
    shl eax, 8
    lea ecx, [rbx + 1]
    sub ecx, r8d
    or eax, ecx
    mov ecx, edx
    rep stosw
.Lnext_symbol:
    inc ebp
    cmp ebp, r15d
    jb .Lplace_symbol
    mov [r12], rbx
    mov rax, r14
    jmp .Ltree_return
.Ltree_error:
    mov rax, -1
.Ltree_return:
    add rsp, TREE_FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.size zstd_huff_tree, .-zstd_huff_tree

# Read ecx bits (at most six) from a short weight stream. rdi is its
# beginning, rsi is the checked remaining bit count. Result in eax.
.Lweight_bits:
    xor eax, eax
    test ecx, ecx
    jz .Lweight_bits_done
.Lweight_bit:
    dec rsi
    mov rdx, rsi
    shr rdx, 3
    movzx edx, byte ptr [rdi + rdx]
    mov r11d, esi
    and r11d, 7
    bt edx, r11d
    adc eax, eax
    dec ecx
    jnz .Lweight_bit
.Lweight_bits_done:
    ret

# Decode exactly one Huffman stream and require exact consumption of its bits.
# rdi=tree, rsi=input, rdx=input length, rcx=destination, r8=output length.
.Lstream:
    push rbx
    push rbp
    test rdx, rdx
    jz .Lstream_error
    lea r9, [rsi + rdx - 1]
    movzx r10d, byte ptr [r9]
    test r10d, r10d
    jz .Lstream_error
    bsr r11d, r10d              # bit count below the end marker
    mov rbx, rcx
    add r8, rbx
    mov edx, [rdi]              # tableLog
    mov ecx, edx
    mov ebp, 1
    shl ebp, cl
    dec ebp                     # lookup mask
.Lstream_symbol:
    cmp rbx, r8
    je .Lstream_finish
.Lstream_fill:
    cmp r11d, edx
    jae .Lfull_index
    cmp r9, rsi
    je .Lshort_index
    dec r9
    shl r10d, 8
    mov r10b, [r9]
    add r11d, 8
    jmp .Lstream_fill
.Lshort_index:
    mov ecx, edx                # lookup padding is ignored by shorter codes
    sub ecx, r11d
    mov eax, r10d
    shl eax, cl
    jmp .Llookup
.Lfull_index:
    mov ecx, r11d
    sub ecx, edx
    mov eax, r10d
    shr eax, cl
.Llookup:
    and eax, ebp
    movzx eax, word ptr [rdi + rax*2 + 8]
    movzx ecx, al
    sub r11d, ecx
    jb .Lstream_error
    shr eax, 8
    mov [rbx], al
    inc rbx
    jmp .Lstream_symbol
.Lstream_finish:
    test r11d, r11d
    jnz .Lstream_error
    cmp r9, rsi
    jne .Lstream_error
    xor eax, eax
    jmp .Lstream_return
.Lstream_error:
    mov eax, -1
.Lstream_return:
    pop rbp
    pop rbx
    ret

# ssize_t zstd_literals(ctx, src, size, dst, capacity, size_t *produced).
# All four literal-block types. A new tree in ctx remains available to later
# treeless blocks. Return the offset of the following sequence section.
.globl zstd_literals
.type zstd_literals,@function
zstd_literals:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov [rsp], r9               # produced pointer
    mov [rsp + 56], r8          # destination capacity
    mov r12, rdi                # tree
    mov rbp, rsi                # current input
    mov r14, rdx                # input bytes available
    mov r13, rcx                # current output
    test r14, r14
    jz .Lliterals_error
    movzx ebx, byte ptr [rbp]
    mov eax, ebx
    and eax, 3
    cmp eax, 2
    jae .Lcompressed
    mov r15d, ebx
    shr r15d, 3                 # one-byte encoding (size formats 0 and 2)
    mov ecx, 1
    test bl, 4
    jz .Lraw_length
    cmp r14, 2
    jb .Lliterals_error
    movzx r15d, word ptr [rbp]
    mov ecx, 2
    test bl, 8
    jz .Lraw_shift
    cmp r14, 3
    jb .Lliterals_error
    movzx eax, byte ptr [rbp + 2]
    shl eax, 16
    or r15d, eax
    inc ecx
.Lraw_shift:
    shr r15d, 4
.Lraw_length:
    cmp r15d, 131072
    ja .Lliterals_error
    cmp r15, [rsp + 56]
    ja .Lliterals_error
    add rbp, rcx
    sub r14, rcx
    mov eax, 1
    test bl, 1
    cmovz rax, r15
    cmp r14, rax
    jb .Lliterals_error
    add rax, rcx
    mov [rsp + 8], rax          # encoded bytes consumed
    mov rcx, r15
    mov rdi, r13
    test bl, 1
    jnz .Lrle
    mov rsi, rbp
    rep movsb
    jmp .Lliterals_done
.Lrle:
    mov al, [rbp]
    rep stosb
    jmp .Lliterals_done

.Lcompressed:
    cmp r14, 3
    jb .Lliterals_error
    movzx eax, word ptr [rbp]
    movzx edx, byte ptr [rbp + 2]
    shl edx, 16
    or eax, edx
    mov ecx, 10                 # bits in each size field
    mov esi, 3                  # header length
    test bl, 8
    jz .Lsplit_sizes
    cmp r14, 4
    jb .Lliterals_error
    mov eax, [rbp]
    mov ecx, 14
    inc esi
    test bl, 4
    jz .Lsplit_sizes
    cmp r14, 5
    jb .Lliterals_error
    movzx edx, byte ptr [rbp + 4]
    shl rdx, 32
    or rax, rdx
    mov ecx, 18
    inc esi
.Lsplit_sizes:
    shr rax, 4
    mov edx, 1
    shl edx, cl
    dec edx
    mov r15d, eax
    and r15d, edx               # regenerated size
    shr rax, cl                 # compressed payload size
    cmp r15d, 131072
    ja .Lliterals_error
    cmp r15, [rsp + 56]
    ja .Lliterals_error
    lea rdx, [rsi + rax]
    cmp r14, rdx
    jb .Lliterals_error
    mov [rsp + 8], rdx
    add rbp, rsi
    mov r14, rax
    test bl, 1
    jnz .Lstreams
    mov rdi, r12
    mov rsi, rbp
    mov rdx, r14
    call zstd_huff_tree
    test rax, rax
    js .Lliterals_error
    add rbp, rax
    sub r14, rax
.Lstreams:
    mov rax, [r12]
    dec rax
    cmp rax, 10                 # require a valid initialized table
    ja .Lliterals_error
    test bl, 12
    jnz .Lfour_streams
    mov rdi, r12
    mov rsi, rbp
    mov rdx, r14
    mov rcx, r13
    mov r8, r15
    call .Lstream
    test eax, eax
    js .Lliterals_error
    jmp .Lliterals_done

.Lfour_streams:
    cmp r14, 6
    jb .Lliterals_error
    sub r14, 6
    xor ecx, ecx
.Ljump_table:
    movzx eax, word ptr [rbp + rcx*2]
    sub r14, rax
    jb .Lliterals_error
    mov [rsp + 32 + rcx*4], eax
    inc ecx
    cmp ecx, 3
    jb .Ljump_table
    mov [rsp + 44], r14d
    add rbp, 6
    lea eax, [r15 + 3]
    shr eax, 2
    mov [rsp + 16], rax         # first three output lengths
    lea edx, [rax + rax*2]
    mov ecx, r15d
    sub ecx, edx
    jb .Lliterals_error
    mov [rsp + 24], rcx         # final output length
    xor ebx, ebx
.Lfour_next:
    mov rdi, r12
    mov rsi, rbp
    mov edx, [rsp + 32 + rbx*4]
    mov rcx, r13
    mov r8, [rsp + 16]
    cmp ebx, 3
    cmove r8, [rsp + 24]
    add rbp, rdx
    add r13, r8
    call .Lstream
    test eax, eax
    js .Lliterals_error
    inc ebx
    cmp ebx, 4
    jb .Lfour_next
.Lliterals_done:
    mov rdi, [rsp]
    mov [rdi], r15
    mov rax, [rsp + 8]
    jmp .Lliterals_return
.Lliterals_error:
    mov rax, -1
.Lliterals_return:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.size zstd_literals, .-zstd_literals
.section .note.GNU-stack,"",@progbits
