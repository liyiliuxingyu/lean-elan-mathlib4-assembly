# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "zstd.inc"
.section .rodata
.balign 8
.Lmixed:
    .long 0xfd2fb528
    .byte 0x24, 43                  # single segment, content checksum
    .byte 16, 0, 0
    .ascii "ab"
    .byte 0x42, 1, 0                # RLE x 40
    .ascii "x"
    .byte 9, 0, 0
    .ascii "."
    .long 0x5f37087c
.equ MIXED_SIZE, . - .Lmixed
.Lextra: .byte 0
.Lexpected: .ascii "ab"
    .fill 40, 1, 'x'
    .ascii "."
.Lempty:
    .long 0xfd2fb528
    .byte 0x24, 0, 1, 0, 0
    .long 0x51d8e999
.equ EMPTY_SIZE, . - .Lempty
.Lbad_checksum:
    .long 0xfd2fb528
    .byte 0x24, 0, 1, 0, 0
    .long 0
.Ldict:
    .long 0xfd2fb528
    .byte 0x63                      # single, 4-byte dict ID, 2-byte FCS
    .long 1598502866
    .word 0                         # decoded size 256
    .byte 3, 8, 0, 7                # final RLE of 256 copies of 7
.equ DICT_SIZE, . - .Ldict
.Lshort_dict:
    .long 0xec30a437, 1598502866     # matches ID but omits entropy tables
.Lwide:
    .long 0xfd2fb528
    .byte 0xd0, 0xff                # unused bit, maximum encoded window
    .quad 0
    .byte 1, 0, 0
.equ WIDE_SIZE, . - .Lwide
.Lbad_reserved:
    .long 0xfd2fb528
    .byte 0x28, 0, 1, 0, 0
.Lbad_block:
    .long 0xfd2fb528
    .byte 0x20, 0, 7, 0, 0
.Lbad_fcs:
    .long 0xfd2fb528
    .byte 0x20, 1, 1, 0, 0
.Lbad_window:
    .long 0xfd2fb528
    .byte 0, 0, 0x0b, 0x20, 0, 7  # window 1024, RLE length 1025
.equ BAD_WINDOW_SIZE, . - .Lbad_window

# verbatim Zstd member of official cache 049953d176d7bde9.ltar,
# file offset 1558, Batteries/Tactic/Lint.ilean.
.Lofficial:
    .byte 0x28,0xb5,0x2f,0xfd,0x00,0x68,0xcd,0x01,0x00,0xe2,0x43
    .byte 0x0d,0x11,0xa0,0xed,0x53,0xb3,0x14,0x3c,0xd9,0x00,0x5a
    .byte 0x78,0xbb,0x53,0x3c,0xe2,0x50,0x15,0x87,0xf3,0xdd,0xb6
    .byte 0x04,0xb4,0x8d,0x8e,0x09,0x4f,0x97,0xb5,0xfb,0x90,0x8f
    .byte 0xeb,0x82,0xc9,0xb1,0x83,0x29,0xc7,0x9f,0xa2,0xa6,0xac
    .byte 0x4a,0xf9,0x40,0x8c,0x37,0xb7,0x8f,0x35,0x5e,0x06,0x00
.equ OFFICIAL_SIZE, . - .Lofficial
.Ljson: .ascii "{\"version\":3,\"references\":{},\"module\":\"Batteries.Tactic.Lint\"}"
.equ JSON_SIZE, . - .Ljson
.bss
.balign 8
.Linfo:     .skip ZSTD_INFO_BYTES
.Lentry:    .skip ZSTD_BLOCK_INFO_BYTES
.Lcursor:   .skip 8
.Lwritten:  .skip 8
.Lmap:      .skip 8
.Lbuf:      .skip 256
.text
.macro inspect object, length, status
    lea rdi, [rip+\object]
    mov esi, \length
    lea rdx, [rip+.Linfo]
    call asm_zstd_inspect
    cmp eax, \status
    jne .Lfail
.endm
.macro decode object, length, cap, status
    lea rdi, [rip+\object]
    mov esi, \length
    lea rdx, [rip+.Lbuf]
    mov ecx, \cap
    lea r8, [rip+.Lwritten]
    call asm_zstd_decode
    cmp eax, \status
    jne .Lfail
.endm
.macro allocate object, length, status
    lea rdi, [rip+\object]
    mov esi, \length
    xor edx, edx
    xor ecx, ecx
    lea r8, [rip+.Lmap]
    lea r9, [rip+.Lwritten]
    call asm_zstd_decode_dict_alloc
    cmp eax, \status
    jne .Lfail
.endm
.macro next type, last, stored, bytes, pos
    lea rdi, [rip+.Lmixed]
    mov esi, MIXED_SIZE
    lea rdx, [rip+.Lcursor]
    lea rcx, [rip+.Lentry]
    call asm_zstd_next_block
    test eax, eax
    jnz .Lfail
    cmp qword ptr [rip+.Lentry+ZSTD_BLOCK_TYPE], \type
    jne .Lfail
    cmp qword ptr [rip+.Lentry+ZSTD_BLOCK_LAST], \last
    jne .Lfail
    cmp qword ptr [rip+.Lentry+ZSTD_BLOCK_STORED], \stored
    jne .Lfail
    cmp qword ptr [rip+.Lentry+ZSTD_BLOCK_SIZE], \bytes
    jne .Lfail
    cmp qword ptr [rip+.Lentry+ZSTD_BLOCK_PAYLOAD], \pos
    jne .Lfail
.endm
.globl _start
_start:
    mov r12d, 1                     # exit code indicates failing group
    inspect .Lmixed, MIXED_SIZE+1, 0
    cmp qword ptr [rip+.Linfo+ZSTD_CONSUMED], MIXED_SIZE
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_HEADER_BYTES], 6
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_WINDOW], 43
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_FLAGS], 7
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_RAW_COUNT], 2
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_RLE_COUNT], 1
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_KNOWN_BLOCK_BYTES], 43
    jne .Lfail
    mov qword ptr [rip+.Lcursor], 6
    next 0, 0, 2, 2, 9
    next 1, 0, 1, 40, 14
    next 0, 1, 1, 1, 18

    inc r12d
    xor ebx, ebx
.Ltruncate:
    lea rdi, [rip+.Lmixed]
    mov rsi, rbx
    lea rdx, [rip+.Linfo]
    call asm_zstd_inspect
    cmp eax, ZSTD_INVALID
    jne .Lfail
    inc ebx
    cmp ebx, MIXED_SIZE
    jb .Ltruncate
    inspect .Lbad_reserved, 9, ZSTD_INVALID
    inspect .Lbad_block, 9, ZSTD_INVALID
    inspect .Lbad_fcs, 9, ZSTD_INVALID
    inspect .Lbad_window, BAD_WINDOW_SIZE, ZSTD_INVALID
    inspect .Lwide, WIDE_SIZE, 0
    movabs rax, 0x3c000000000
    cmp [rip+.Linfo+ZSTD_WINDOW], rax
    jne .Lfail
    inspect .Ldict, DICT_SIZE, 0
    cmp qword ptr [rip+.Linfo+ZSTD_DICT_ID], 1598502866
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_CONTENT_SIZE], 256
    jne .Lfail
    decode .Ldict, DICT_SIZE, 256, ZSTD_DICTIONARY
    lea rdi, [rip+.Ldict]
    mov esi, DICT_SIZE
    lea rdx, [rip+.Lshort_dict]
    mov ecx, 8
    lea r8, [rip+.Lmap]
    lea r9, [rip+.Lwritten]
    call asm_zstd_decode_dict_alloc
    cmp eax, ZSTD_INVALID
    jne .Lfail
    cmp qword ptr [rip+.Lmap], 0
    jne .Lfail

    inc r12d
    decode .Lmixed, MIXED_SIZE+1, 43, 0
    cmp qword ptr [rip+.Lwritten], 43
    jne .Lfail
    lea rsi, [rip+.Lbuf]
    lea rdi, [rip+.Lexpected]
    mov ecx, 43
    repe cmpsb
    jne .Lfail
    decode .Lmixed, MIXED_SIZE, 42, ZSTD_CAPACITY
    cmp qword ptr [rip+.Lwritten], 0
    jne .Lfail
    decode .Lempty, EMPTY_SIZE, 0, 0
    decode .Lbad_checksum, EMPTY_SIZE, 0, ZSTD_CHECKSUM
    allocate .Lmixed, MIXED_SIZE+1, ZSTD_INVALID
    cmp qword ptr [rip+.Lmap], 0
    jne .Lfail
    allocate .Lempty, EMPTY_SIZE, 0
    mov rdi, [rip+.Lmap]
    mov esi, 1
    mov eax, 11
    syscall
    test eax, eax
    jnz .Lfail

    inc r12d
    inspect .Lofficial, OFFICIAL_SIZE, 0
    cmp qword ptr [rip+.Linfo+ZSTD_WINDOW], 8388608
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_FLAGS], 0
    jne .Lfail
    cmp qword ptr [rip+.Linfo+ZSTD_COMPRESSED_COUNT], 1
    jne .Lfail
    allocate .Lofficial, OFFICIAL_SIZE, 0
    cmp qword ptr [rip+.Lwritten], JSON_SIZE
    jne .Lfail
    mov rsi, [rip+.Lmap]
    lea rdi, [rip+.Ljson]
    mov ecx, JSON_SIZE
    repe cmpsb
    jne .Lfail
    mov rdi, [rip+.Lmap]
    mov esi, JSON_SIZE
    mov eax, 11
    syscall
    test eax, eax
    jnz .Lfail

    xor r12d, r12d
.Lfail:
    mov edi, r12d
    mov eax, 60
    syscall
.section .note.GNU-stack,"",@progbits
