# SPDX-License-Identifier: Apache-2.0
# One ordinary Zstandard frame. See RFC 8878 sections 3.1.1.1-2.
.intel_syntax noprefix
.include "zstd.inc"
.equ BLOCK_LIMIT, 131072
.text

# Read exactly three bytes. The fourth can lie beyond the mapping.
.macro block_header header, scratch, cursor
    movzx \header, word ptr [\cursor]
    movzx \scratch, byte ptr [\cursor+2]
    shl \scratch, 16
    or \header, \scratch
.endm

# int asm_zstd_inspect(const void *src, size_t size, struct info *out)
# Only checks the frame envelope. Bytes after this frame are permitted.
.globl asm_zstd_inspect
.type asm_zstd_inspect,@function
asm_zstd_inspect:
    mov r8, rdi                       # original source
    mov r9, rdx                       # result
    mov r10, rsi
    add r10, rdi                      # end of accessible input
    jc .Lbad_frame
    cmp rsi, 5
    jb .Lbad_frame
    cmp dword ptr [rdi], 0xfd2fb528
    jne .Lbad_frame
    movzx r11d, byte ptr [rdi+4]
    test r11b, 8                      # reserved; bit 4 is ignored by decoders
    jnz .Lbad_frame
    mov rdi, r9
    xor eax, eax
    mov ecx, ZSTD_INFO_BYTES/8
    rep stosq
    lea rdi, [r8+5]                   # input cursor
    mov qword ptr [r9+ZSTD_CONTENT_SIZE], -1
    test r11b, 4
    jz .Lsegment
    or byte ptr [r9+ZSTD_FLAGS], ZSTD_HAS_CHECKSUM
.Lsegment:
    test r11b, 32
    jz .Lwindow_descriptor
    or byte ptr [r9+ZSTD_FLAGS], ZSTD_SINGLE_SEGMENT
    jmp .Ldictionary
.Lwindow_descriptor:
    cmp rdi, r10
    jae .Lbad_frame
    movzx eax, byte ptr [rdi]
    inc rdi
    mov ecx, eax
    shr ecx, 3
    add ecx, 7
    and eax, 7
    add eax, 8
    shl rax, cl                       # (8 + mantissa) * windowBase / 8
    mov [r9+ZSTD_WINDOW], rax
.Ldictionary:
    mov eax, r11d
    and eax, 3
    jz .Lcontent
    cmp eax, 3
    jne .Ldict_width
    inc eax
.Ldict_width:
    mov ecx, eax
    call .Lfield
    jc .Lbad_frame
    mov [r9+ZSTD_DICT_ID], rax
.Lcontent:
    mov ecx, r11d
    shr ecx, 6
    test ecx, ecx
    jnz .Lcontent_width
    test r11b, 32
    jz .Lblocks
.Lcontent_width:
    mov eax, 1
    shl eax, cl
    mov ecx, eax
    call .Lfield
    jc .Lbad_frame
    cmp ecx, 2
    jne .Lset_size
    add eax, 256
.Lset_size:
    or byte ptr [r9+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    mov [r9+ZSTD_CONTENT_SIZE], rax
    test r11b, 32
    jz .Lblocks
    mov [r9+ZSTD_WINDOW], rax
.Lblocks:
    mov rax, rdi
    sub rax, r8
    mov [r9+ZSTD_HEADER_BYTES], rax
    mov r11d, 131072
    cmp r11, [r9+ZSTD_WINDOW]
    cmova r11, [r9+ZSTD_WINDOW]
.Lnext_block:
    mov rsi, r10
    sub rsi, rdi
    cmp rsi, 3
    jb .Lbad_frame
    block_header edx, eax, rdi
    add rdi, 3
    sub rsi, 3
    mov ecx, edx
    shr ecx, 3
    cmp rcx, r11
    ja .Lbad_frame
    mov eax, edx
    shr eax, 1
    and eax, 3
    cmp eax, 3
    je .Lbad_frame
    inc qword ptr [r9+ZSTD_RAW_COUNT+rax*8]
    cmp eax, 2
    je .Lcompressed_block
    add [r9+ZSTD_KNOWN_BLOCK_BYTES], rcx
    jc .Lbad_frame
    test eax, eax
    jz .Lpayload
    mov ecx, 1                        # RLE always stores one byte
    jmp .Lpayload
.Lcompressed_block:
    cmp ecx, 2                        # minimal literal and sequence headers
    jb .Lbad_frame
.Lpayload:
    cmp rcx, rsi
    ja .Lbad_frame
    add rdi, rcx
    test dl, 1
    jz .Lnext_block
    test byte ptr [r9+ZSTD_FLAGS], ZSTD_HAS_CHECKSUM
    jz .Lcheck_size
    mov rax, r10
    sub rax, rdi
    cmp rax, 4
    jb .Lbad_frame
    add rdi, 4
.Lcheck_size:
    test byte ptr [r9+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    jz .Lfinish_frame
    mov rax, [r9+ZSTD_KNOWN_BLOCK_BYTES]
    cmp rax, [r9+ZSTD_CONTENT_SIZE]
    ja .Lbad_frame
    je .Lfinish_frame
    cmp qword ptr [r9+ZSTD_COMPRESSED_COUNT], 0
    je .Lbad_frame
.Lfinish_frame:
    sub rdi, r8
    mov [r9+ZSTD_CONSUMED], rdi
    xor eax, eax
    ret
.Lbad_frame:
    mov eax, ZSTD_INVALID
    ret

# Read ecx = 1, 2, 4 or 8 little-endian bytes, preserving ecx.
.Lfield:
    mov rax, r10
    sub rax, rdi
    cmp rax, rcx
    jb .Lfield_bad
    cmp ecx, 1
    je .Lbyte
    cmp ecx, 2
    je .Lword
    cmp ecx, 4
    je .Ldword
    mov rax, [rdi]
    jmp .Lfield_ok
.Lbyte:
    movzx eax, byte ptr [rdi]
    jmp .Lfield_ok
.Lword:
    movzx eax, word ptr [rdi]
    jmp .Lfield_ok
.Ldword:
    mov eax, [rdi]
.Lfield_ok:
    add rdi, rcx
    clc
    ret
.Lfield_bad:
    stc
    ret
.size asm_zstd_inspect,.-asm_zstd_inspect

# int asm_zstd_next_block(src, size, size_t *offset, struct block *out)
# Begin at info.header_bytes. After a successful call offset points beyond
# the payload. Stop when out.last is set, before the optional checksum.
.globl asm_zstd_next_block
.type asm_zstd_next_block,@function
asm_zstd_next_block:
    mov r8, [rdx]
    sub rsi, r8
    jb .Lbad_block
    cmp rsi, 3
    jb .Lbad_block
    add rdi, r8
    jc .Lbad_block
    block_header eax, r9d, rdi
    sub rsi, 3
    add r8, 3                         # position of block data
    mov r9d, eax
    shr r9d, 1
    and r9d, 3
    cmp r9d, 3
    je .Lbad_block
    mov r10d, eax
    shr r10d, 3                       # size in block header
    cmp r10d, BLOCK_LIMIT
    ja .Lbad_block
    mov r11d, r10d                    # size physically stored
    cmp r9d, 1
    jne .Ldirectory_range
    mov r11d, 1
.Ldirectory_range:
    cmp r11, rsi
    ja .Lbad_block
    and eax, 1
    mov [rcx+ZSTD_BLOCK_PAYLOAD], r8
    mov [rcx+ZSTD_BLOCK_STORED], r11
    mov [rcx+ZSTD_BLOCK_SIZE], r10
    mov [rcx+ZSTD_BLOCK_TYPE], r9
    mov [rcx+ZSTD_BLOCK_LAST], rax
    add r8, r11
    mov [rdx], r8
    xor eax, eax
    ret
.Lbad_block:
    mov eax, ZSTD_INVALID
    ret
.size asm_zstd_next_block,.-asm_zstd_next_block

# int asm_zstd_decode(src, size, dst, capacity, size_t *written)
# Private decode_frame() additionally accepts a dictionary pointer in r9 and
# its length on the stack. A complete frame prefix is sufficient in this API.
.globl asm_zstd_decode
.type asm_zstd_decode,@function
asm_zstd_decode:
    xor r9d, r9d
    push 0
    call .Ldecode_frame
    add rsp, 8
    ret
.size asm_zstd_decode,.-asm_zstd_decode

# Fixed scratch for the three inter-block FSE tables, Huffman table, repeat
# offsets, and current block literals. mmap only for a compressed block.
.equ ENTROPY_BYTES, 32768
.equ WORK_BYTES, ENTROPY_BYTES + BLOCK_LIMIT
.equ D_WORK, 80                        # mmap base, zero unless allocated
.equ D_DICT, 88
.equ D_DICTLEN, 96
.equ D_LITS, 104                       # literal count out-parameter
.equ D_BSIZE, 112                      # per-frame block size limit
.equ D_LIMIT, 120                      # capacity sent to sequence decoder
.equ D_LOCALS, 136
.Ldecode_frame:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, D_LOCALS
    mov rbx, rdi                      # input cursor
    mov r12, rdx                      # output base
    mov r13, rcx                      # destination capacity
    mov r14, r8                       # written-out parameter
    xor r15d, r15d                    # bytes produced
    mov [r14], r15
    mov [rsp+D_WORK], r15
    mov [rsp+D_DICT], r9
    mov rax, [rsp+D_LOCALS+48+8]
    mov [rsp+D_DICTLEN], rax
    mov rdx, rsp
    call asm_zstd_inspect
    test eax, eax
    jnz .Ldecode_done
    mov rdx, [rsp+ZSTD_DICT_ID]
    test rdx, rdx
    jz .Lcheck_capacity
    cmp qword ptr [rsp+D_DICTLEN], 8
    jb .Ldictionary_needed
    mov rdi, [rsp+D_DICT]
    cmp dword ptr [rdi], 0xec30a437
    jne .Ldictionary_needed
    cmp edx, [rdi+4]
    jne .Ldictionary_needed
.Lcheck_capacity:
    cmp qword ptr [rsp+D_DICTLEN], 0
    je .Ldestination
    cmp qword ptr [rsp+D_DICTLEN], 8  # RFC 8878 §5, minimum raw history
    jb .Linvalid_output
.Ldestination:
    mov rax, r12
    add rax, r13
    jc .Ltoo_small
    test byte ptr [rsp+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    jz .Lprepare_blocks
    cmp r13, [rsp+ZSTD_CONTENT_SIZE]
    jb .Ltoo_small
.Lprepare_blocks:
    mov ecx, BLOCK_LIMIT
    cmp rcx, [rsp+ZSTD_WINDOW]
    cmova rcx, [rsp+ZSTD_WINDOW]
    mov [rsp+D_BSIZE], rcx
    cmp qword ptr [rsp+ZSTD_COMPRESSED_COUNT], 0
    jne .Lentropy
    cmp qword ptr [rsp+D_DICTLEN], 4
    jb .Ldecode_blocks
    mov rdi, [rsp+D_DICT]
    cmp dword ptr [rdi], 0xec30a437
    jne .Ldecode_blocks
.Lentropy:
    mov esi, WORK_BYTES
    call .Lmmap
    cmp rax, -4095
    jae .Lno_memory
    mov [rsp+D_WORK], rax
    mov rdi, rax
    mov rsi, [rsp+D_DICT]
    mov rdx, [rsp+D_DICTLEN]
    mov rcx, [rsp+ZSTD_WINDOW]
    call z6_entropy_init
    test eax, eax
    jnz .Linvalid_output
.Ldecode_blocks:
    add rbx, [rsp+ZSTD_HEADER_BYTES]
.Ldecode_block:
    block_header ebp, eax, rbx
    add rbx, 3
    mov ecx, ebp
    shr ecx, 3                        # block size
    mov eax, ebp
    and eax, 6
    cmp eax, 4
    je .Ldecode_compressed
    mov rdx, r13
    sub rdx, r15
    cmp rdx, rcx
    jb .Ltoo_small
    lea rdi, [r12+r15]
    add r15, rcx
    test eax, eax
    jz .Lcopy_raw
    mov al, [rbx]
    inc rbx
    rep stosb
    jmp .Lblock_complete
.Lcopy_raw:
    mov rsi, rbx
    add rbx, rcx
    rep movsb
    jmp .Lblock_complete
.Ldecode_compressed:
    mov rsi, rbx                      # start of block payload
    add rbx, rcx                      # save next header / checksum address
    mov rdx, rcx
    mov rdi, [rsp+D_WORK]
    lea rcx, [rdi+ENTROPY_BYTES]      # literals scratch
    mov r8, [rsp+D_BSIZE]
    lea r9, [rsp+D_LITS]
    call zstd_literals
    test rax, rax
    js .Linvalid_output
    mov edx, ebp
    shr edx, 3
    sub rdx, rax                      # encoded sequence-section length
    jbe .Linvalid_output              # mandatory number-of-sequences byte
    mov rsi, rbx
    sub rsi, rdx                      # sequence-section start
    mov rdi, [rsp+D_WORK]
    lea rcx, [rdi+ENTROPY_BYTES]
    mov r8, [rsp+D_LITS]
    mov r9, r12
    mov rax, r13
    sub rax, r15
    cmp rax, [rsp+D_BSIZE]
    cmova rax, [rsp+D_BSIZE]
    add rax, r15
    mov [rsp+D_LIMIT], rax
    push rax                          # absolute capacity up through this block
    push r15                          # prior frame output bytes
    call z6_sequences
    add rsp, 16
    cmp rax, -2
    je .Lsequence_capacity
    test rax, rax
    js .Linvalid_output
    add r15, rax
    cmp r15, [rsp+D_LIMIT]
    ja .Linvalid_output
.Lblock_complete:
    test bpl, 1
    jz .Ldecode_block
    test byte ptr [rsp+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    jz .Lmaybe_checksum
    cmp r15, [rsp+ZSTD_CONTENT_SIZE]
    jne .Linvalid_output
.Lmaybe_checksum:
    test byte ptr [rsp+ZSTD_FLAGS], ZSTD_HAS_CHECKSUM
    jz .Lsuccess
    mov rdi, r12
    mov rsi, r15
    call asm_zstd_xxh64
    cmp eax, [rbx]
    jne .Lchecksum_error
.Lsuccess:
    mov [r14], r15
    xor eax, eax
    jmp .Ldecode_done
.Lsequence_capacity:
    mov rax, r13
    sub rax, r15
    cmp rax, [rsp+D_BSIZE]
    jae .Linvalid_output              # block output violates window/128 KiB
    test byte ptr [rsp+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    jnz .Linvalid_output              # supplied capacity already covered FCS
.Ltoo_small:
    mov eax, ZSTD_CAPACITY
    jmp .Ldecode_done
.Ldictionary_needed:
    mov eax, ZSTD_DICTIONARY
    jmp .Ldecode_done
.Linvalid_output:
    mov eax, ZSTD_INVALID
    jmp .Ldecode_done
.Lchecksum_error:
    mov eax, ZSTD_CHECKSUM
    jmp .Ldecode_done
.Lno_memory:
    mov eax, ZSTD_ALLOC
.Ldecode_done:
    mov rdi, [rsp+D_WORK]
    test rdi, rdi
    jz .Ldecode_return
    mov ebx, eax
    mov esi, WORK_BYTES
    mov eax, 11                       # munmap work
    syscall
    mov eax, ebx
.Ldecode_return:
    add rsp, D_LOCALS
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# int asm_zstd_decode_dict_alloc(src,len,dict,dictlen,void **out,size_t *size)
# Require exactly one frame. Reserve at most the aggregate possible decoded
# size, trim unused pages after decoding, and publish only a verified result.
.globl asm_zstd_decode_dict_alloc
.type asm_zstd_decode_dict_alloc,@function
asm_zstd_decode_dict_alloc:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 104
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov [rsp+80], r8
    mov [rsp+88], r9
    mov qword ptr [r8], 0
    mov qword ptr [r9], 0
    mov rdx, rsp
    call asm_zstd_inspect
    test eax, eax
    jnz .Lalloc_done
    cmp r13, [rsp+ZSTD_CONSUMED]
    jne .Lalloc_invalid
    mov eax, BLOCK_LIMIT
    cmp rax, [rsp+ZSTD_WINDOW]
    cmova rax, [rsp+ZSTD_WINDOW]
    mul qword ptr [rsp+ZSTD_COMPRESSED_COUNT]
    test rdx, rdx
    jnz .Lalloc_large
    add rax, [rsp+ZSTD_KNOWN_BLOCK_BYTES]
    jnc .Lalloc_bound
.Lalloc_large:
    mov rax, -1
.Lalloc_bound:
    test byte ptr [rsp+ZSTD_FLAGS], ZSTD_HAS_CONTENT_SIZE
    jz .Lalloc_map
    cmp rax, [rsp+ZSTD_CONTENT_SIZE]
    jb .Lalloc_invalid
    mov rax, [rsp+ZSTD_CONTENT_SIZE]
.Lalloc_map:
    test rax, rax
    jnz .Lalloc_nonempty
    inc eax                           # caller can munmap max(1,size)
.Lalloc_nonempty:
    mov rbp, rax                      # reserved size
    mov rsi, rax
    call .Lmmap
    cmp rax, -4095
    jae .Lalloc_error
    mov rbx, rax                      # output mapping
    mov rdi, r12
    mov rsi, r13
    mov rdx, rbx
    mov rcx, rbp
    lea r8, [rsp+96]                  # result length
    mov r9, r14
    sub rsp, 8                        # maintain SysV stack alignment
    push r15
    call .Ldecode_frame
    add rsp, 16
    test eax, eax
    jnz .Lalloc_discard
    mov rax, [rsp+96]
    mov rcx, [rsp+88]
    mov [rcx], rax
    mov rcx, [rsp+80]
    mov [rcx], rbx
    mov ecx, 1
    test rax, rax
    cmovz rax, rcx
    add rax, 4095                     # Linux x86-64 base page size
    and rax, -4096
    cmp rax, rbp
    jae .Lalloc_success
    lea rdi, [rbx+rax]
    mov rsi, rbp
    sub rsi, rax
    mov eax, 11
    syscall
.Lalloc_success:
    xor eax, eax
    jmp .Lalloc_done
.Lalloc_discard:
    mov r12d, eax
    mov rdi, rbx
    mov rsi, rbp
    mov eax, 11
    syscall
    mov eax, r12d
    jmp .Lalloc_done
.Lalloc_invalid:
    mov eax, ZSTD_INVALID
    jmp .Lalloc_done
.Lalloc_error:
    mov eax, ZSTD_ALLOC
.Lalloc_done:
    add rsp, 104
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size asm_zstd_decode_dict_alloc,.-asm_zstd_decode_dict_alloc

.Lmmap:
    xor edi, edi
    mov edx, 3                        # PROT_READ | PROT_WRITE
    mov r10d, 34                      # MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    ret
.section .note.GNU-stack,"",@progbits
