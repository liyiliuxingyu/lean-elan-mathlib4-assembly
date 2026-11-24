# SPDX-License-Identifier: Apache-2.0
# Native ABI tests for declaration and query keys, with a relocatable file image.
.intel_syntax noprefix
.include "olean_layout.inc"
.equ BASE, 0x200000
.macro ptr name
    .quad BASE + \name - .Limage
.endm
.macro hdr tag, fields, size
    .long 0
    .short \size
    .byte \fields, \tag
.endm
.data
.balign 8
.Limage: .zero 96
.Lstr:
    hdr 249, 0, 1
    .quad 4, 4, 3
    .asciz "x.y"
.balign 8
.Lfirst:
    hdr 1, 2, 32
    .quad 1
    ptr .Lstr
    .quad 0
.Llast:
    hdr 2, 2, 32
    ptr .Lfirst
    .quad 15, 0
.Lchain:
    .rept 65
        hdr 1, 2, 32
        .quad BASE + (. - 8) - .Limage - 32
        ptr .Lstr
        .quad 0
    .endr
.Lbig:
    hdr 250, 0, 32
    .long 1, 1
    ptr .Llimb
.Llimb: .quad 0x8000000000000000
.Lconstant:
    hdr 1, 1, 16
    .quad 1
.Lnames: ptr .Llast
.Lconsts: ptr .Lconstant
.Lend:
.Lview:
    .quad .Limage, .Lend - .Limage, BASE, .Lnames, .Lconsts, 1, 0, 0
.Lkind: .quad 99
.section .rodata
.Ltext: .asciz "«x.y».007"
.Lbadtext: .asciz "x.9223372036854775808"
.Lempty: .asciz "«».7"
.Lspace: .asciz "« a ».7"
.Ldel:   .asciz "«x\177y».7"
.Lleft:  .asciz "«x«».7"
.Lexpected:
    .byte 1
    .quad 3
    .ascii "x.y"
    .byte 2
    .quad 7
.equ SIZE, . - .Lexpected
.bss
.Lbuf: .zero SIZE
.Lquery_buf: .zero SIZE

.macro eq actual, expected
    inc ebx
    cmp \actual, \expected
    jne .Lfail
.endm
.macro declare name, cap=0, buffer=0
    mov qword ptr [rip+.Lnames], \name
    lea rdi, [rip+.Lview]
    xor esi, esi
    xor edx, edx
    .if \buffer
        lea rdx, [rip+.Lbuf]
    .endif
    mov ecx, \cap
    lea r8, [rip+.Lkind]
    call catalog_key_decl
.endm
.macro output_matches
    inc ebx
    lea rdi, [rip+.Lbuf]
    lea rsi, [rip+.Lexpected]
    mov ecx, SIZE
    repe cmpsb
    jne .Lfail
.endm
# The modified declaration string must be spellable by the given argv query.
.macro spell query, length
    declare LAST, SIZE, 1
    eq rax, \length
    lea rdi, [rip+\query]
    lea rsi, [rip+.Lquery_buf]
    mov edx, SIZE
    call catalog_key_query
    eq rax, \length
    inc ebx
    lea rsi, [rip+.Lquery_buf]
    lea rdi, [rip+.Lbuf]
    mov ecx, \length
    repe cmpsb
    jne .Lfail
.endm
.equ LAST, BASE + .Llast - .Limage
.equ CHAIN, BASE + .Lchain - .Limage
.equ BIG, BASE + .Lbig - .Limage
.text
.globl _start
.type _start,@function
_start:
    xor ebx, ebx
    declare LAST
    eq rax, SIZE
    eq "qword ptr [rip+.Lkind]", 1
    declare LAST, SIZE, 1
    eq rax, SIZE
    output_matches
    mov byte ptr [rip+.Lbuf], 0
    declare LAST, SIZE-1, 1
    eq rax, -2
    eq "byte ptr [rip+.Lbuf]", 0
    lea rdi, [rip+.Ltext]
    lea rsi, [rip+.Lbuf]
    mov edx, SIZE
    call catalog_key_query
    eq rax, SIZE
    output_matches
    lea rdi, [rip+.Lbadtext]
    xor esi, esi
    xor edx, edx
    call catalog_key_query
    eq rax, -1

    # 64 components are encodable; validate a 65th and its entire prefix.
    mov qword ptr [rip+.Lchain+8], 1
    declare CHAIN+63*32
    eq rax, 64*12
    declare CHAIN+64*32
    eq rax, -3
    mov qword ptr [rip+.Lchain+8], CHAIN+32
    declare CHAIN+64*32
    eq rax, -1
    mov qword ptr [rip+.Lchain+8], 0
    declare CHAIN+64*32
    eq rax, -1

    declare 1
    eq rax, -3
    mov qword ptr [rip+.Llast+16], BIG
    declare LAST
    eq rax, -3
    mov dword ptr [rip+.Lbig+12], -1
    declare LAST
    eq rax, -1
    mov dword ptr [rip+.Lbig+12], 1
    inc qword ptr [rip+.Lbig+16]
    declare LAST
    eq rax, -1
    mov qword ptr [rip+.Llast+16], 15
    mov byte ptr [rip+.Lstr+35], 1
    declare LAST
    eq rax, -1
    mov byte ptr [rip+.Lstr+35], 0
    mov byte ptr [rip+.Lstr+33], 0   # Embedded NUL, before the final NUL.
    declare LAST
    eq rax, -3
    mov byte ptr [rip+.Lstr+33], 31
    declare LAST
    eq rax, -3
    mov word ptr [rip+.Lstr+33], 0xbbc2  # U+00BB is always a delimiter.
    declare LAST
    eq rax, -3
    mov qword ptr [rip+.Lfirst+8], CHAIN    # Keep walking invalid prefixes.
    declare LAST
    eq rax, -1
    mov qword ptr [rip+.Lfirst+8], 1
    mov word ptr [rip+.Lstr+33], 0xabc2
    spell .Lleft, SIZE
    mov dword ptr [rip+.Lstr+32], 0x00206120
    spell .Lspace, SIZE
    mov dword ptr [rip+.Lstr+32], 0x00797f78
    spell .Ldel, SIZE
    mov byte ptr [rip+.Lstr+32], 0
    mov qword ptr [rip+.Lstr+8], 1
    mov qword ptr [rip+.Lstr+16], 1
    mov qword ptr [rip+.Lstr+24], 0
    spell .Lempty, SIZE-3
    mov byte ptr [rip+.Lconstant+7], 2
    declare LAST                     # Malformed TheoremVal pointer.
    eq rax, -1
    xor edi, edi
    jmp .Lexit
.Lfail:
    mov edi, ebx
.Lexit:
    mov eax, 60
    syscall
.size _start, .-_start
.section .note.GNU-stack,"",@progbits
