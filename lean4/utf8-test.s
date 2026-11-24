# Standalone GNU as / ld tests for the Lean 4 UTF-8 runtime port.
# Exit codes identify the failing group (1 widths, 2 continuation,
# 3 lengths, 4 last character, 5 validation, 6 decoding, 7 encoding).
.intel_syntax noprefix

.section .rodata
.Lmixed:
    .byte 0x61, 0xc2, 0xa2, 0xe4, 0xbd, 0xa0, 0xf0, 0x9f, 0x98, 0x80, 0
.Lwith_nul:
    .byte 0x61, 0, 0xc2, 0xa2, 0
.Llegacy:
    .byte 0xf8, 0x80, 0x80, 0x80, 0x80, 0xfd, 0x80, 0x80, 0x80, 0x80, 0x80, 0xfe, 0
.Ltwo_low:       .byte 0xc2, 0x80
.Ltwo_high:      .byte 0xdf, 0xbf
.Ltwo_overlong:  .byte 0xc1, 0xbf
.Ltwo_bad_tail:  .byte 0xc2, 0x01
.Lthree_low:     .byte 0xe0, 0xa0, 0x80
.Lthree_short:   .byte 0xe0, 0x9f, 0xbf
.Lthree_before:  .byte 0xed, 0x9f, 0xbf
.Lthree_sur:     .byte 0xed, 0xa0, 0x80
.Lthree_after:   .byte 0xee, 0x80, 0x80
.Lfour_low:      .byte 0xf0, 0x90, 0x80, 0x80
.Lfour_short:    .byte 0xf0, 0x8f, 0xbf, 0xbf
.Lfour_high:     .byte 0xf4, 0x8f, 0xbf, 0xbf
.Lfour_large:    .byte 0xf4, 0x90, 0x80, 0x80
.Lfour_bad_tail: .byte 0xf0, 0x90, 0x00, 0x80
.Lprefixed_bad:  .byte 0x61, 0xc2, 0x01, 0x61
.align 8
# str, size, initial position, return value, final position, scalars processed.
.Lvalidate_cases:
    .quad .Lwith_nul, 5, 0, 1, 5, 4
    .quad .Lmixed, 10, 0, 1, 10, 4
    .quad .Lmixed, 10, 3, 1, 10, 2
    .quad .Lmixed, 10, 10, 1, 10, 0
    .quad .Lmixed, 10, 11, 1, 11, 0
    .quad .Lmixed, 9, 0, 0, 6, 3
    .quad .Ltwo_low, 2, 0, 1, 2, 1
    .quad .Ltwo_high, 2, 0, 1, 2, 1
    .quad .Ltwo_high, 1, 0, 0, 0, 0
    .quad .Ltwo_overlong, 2, 0, 0, 0, 0
    .quad .Ltwo_bad_tail, 2, 0, 0, 0, 0
    .quad .Lthree_low, 3, 0, 1, 3, 1
    .quad .Lthree_short, 3, 0, 0, 0, 0
    .quad .Lthree_before, 3, 0, 1, 3, 1
    .quad .Lthree_sur, 3, 0, 0, 0, 0
    .quad .Lthree_after, 3, 0, 1, 3, 1
    .quad .Lfour_low, 4, 0, 1, 4, 1
    .quad .Lfour_short, 4, 0, 0, 0, 0
    .quad .Lfour_high, 4, 0, 1, 4, 1
    .quad .Lfour_large, 4, 0, 0, 0, 0
    .quad .Lfour_bad_tail, 4, 0, 0, 0, 0
    .quad .Lprefixed_bad, 4, 0, 0, 1, 1
    .quad .Llegacy, 12, 0, 0, 0, 0
.Lvalidate_end:

# str, size, initial position, decoded value, final position.
.Ldecode_cases:
    .quad .Lmixed, 10, 0, 0x61, 1
    .quad .Lmixed, 10, 1, 0xa2, 3
    .quad .Lmixed, 10, 3, 0x4f60, 6
    .quad .Lmixed, 10, 6, 0x1f600, 10
    .quad .Lmixed, 9, 6, 0xf0, 7
    .quad .Ltwo_low, 2, 0, 0x80, 2
    .quad .Ltwo_high, 2, 0, 0x7ff, 2
    .quad .Ltwo_overlong, 2, 0, 0xc1, 1
    .quad .Ltwo_bad_tail, 2, 0, 0x81, 2
    .quad .Lthree_low, 3, 0, 0x800, 3
    .quad .Lthree_short, 3, 0, 0xe0, 1
    .quad .Lthree_before, 3, 0, 0xd7ff, 3
    .quad .Lthree_sur, 3, 0, 0xed, 1
    .quad .Lthree_after, 3, 0, 0xe000, 3
    .quad .Lfour_low, 4, 0, 0x10000, 4
    .quad .Lfour_short, 4, 0, 0xf0, 1
    .quad .Lfour_high, 4, 0, 0x10ffff, 4
    .quad .Lfour_large, 4, 0, 0xf4, 1
    .quad .Lfour_bad_tail, 4, 0, 0x10000, 4
    .quad .Llegacy, 12, 0, 0xf8, 1
.Ldecode_end:

# Scalar, bytes written, entire four-byte destination with untouched bytes.
.Lencode_cases:
    .long 0, 1, 0xaaaaaaaa & 0xffffff00
    .long 0x7f, 1, 0xaaaaaa7f
    .long 0x80, 2, 0xaaaa80c2
    .long 0x7ff, 2, 0xaaaabfdf
    .long 0x800, 3, 0xaa80a0e0
    .long 0xd800, 3, 0xaa80a0ed
    .long 0xffff, 3, 0xaabfbfef
    .long 0x10000, 4, 0x808090f0
    .long 0x10ffff, 4, 0xbfbf8ff4
    .long 0xffffffff, 4, 0xbfbfbff7
.Lencode_end:

.bss
.align 8
.Lposition: .zero 8
.Lcount: .zero 8
.Lencoded: .zero 4

.text
.globl _start
.type _start, @function
_start:
    xor r12d, r12d
.Lcheck_byte:
    mov edi, r12d
    call _ZN4lean13get_utf8_sizeEh
    mov edx, 1
    cmp r12d, 0xc0
    jb .Lwidth_expected
    cmp r12d, 0xfe
    jae .Lwidth_expected
    inc edx
    cmp r12d, 0xe0
    jb .Lwidth_expected
    inc edx
    cmp r12d, 0xf0
    jb .Lwidth_expected
    inc edx
    cmp r12d, 0xf8
    jb .Lwidth_expected
    inc edx
    cmp r12d, 0xfc
    jb .Lwidth_expected
    inc edx
.Lwidth_expected:
    cmp eax, edx
    jne .Lfail_width
    mov edi, r12d
    call _ZN4lean12is_utf8_nextEh
    lea edx, [r12d - 0x80]
    cmp edx, 64
    setb dl
    cmp al, dl
    jne .Lfail_cont
    inc r12d
    cmp r12d, 256
    jne .Lcheck_byte

    lea rdi, [rip + .Lmixed]
    call lean_utf8_strlen
    cmp rax, 4
    jne .Lfail_strlen
    lea rdi, [rip + .Lwith_nul]
    call _ZN4lean11utf8_strlenEPKc
    cmp rax, 1
    jne .Lfail_strlen
    lea rdi, [rip + .Lwith_nul]
    mov esi, 5
    call lean_utf8_n_strlen
    cmp rax, 4
    jne .Lfail_strlen
    lea rdi, [rip + .Lmixed + 6]
    mov esi, 1
    call _ZN4lean11utf8_strlenEPKcm
    cmp rax, 1
    jne .Lfail_strlen
    xor edi, edi
    xor esi, esi
    call lean_utf8_n_strlen
    test rax, rax
    jne .Lfail_strlen
    lea rdi, [rip + .Llegacy]
    call lean_utf8_strlen
    cmp rax, 3
    jne .Lfail_strlen

    lea rdi, [rip + .Lmixed]
    call _ZN4lean18get_utf8_last_charEPKc
    lea rdx, [rip + .Lmixed + 6]
    cmp rax, rdx
    jne .Lfail_last

    lea r12, [rip + .Lvalidate_cases]
    lea r13, [rip + .Lvalidate_end]
.Lcheck_validate:
    mov rax, [r12 + 16]
    mov [rip + .Lposition], rax
    mov qword ptr [rip + .Lcount], 19
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    lea rdx, [rip + .Lposition]
    lea rcx, [rip + .Lcount]
    call _ZN4lean13validate_utf8EPKhmRmS2_
    cmp al, [r12 + 24]
    jne .Lfail_validate
    mov rax, [rip + .Lposition]
    cmp rax, [r12 + 32]
    jne .Lfail_validate
    mov rax, [rip + .Lcount]
    sub rax, 19
    cmp rax, [r12 + 40]
    jne .Lfail_validate
    add r12, 48
    cmp r12, r13
    jne .Lcheck_validate

    lea r12, [rip + .Ldecode_cases]
    lea r13, [rip + .Ldecode_end]
.Lcheck_decode:
    mov rax, [r12 + 16]
    mov [rip + .Lposition], rax
    mov rdi, [r12]
    mov rsi, [r12 + 8]
    lea rdx, [rip + .Lposition]
    call _ZN4lean9next_utf8EPKcmRm
    cmp rax, [r12 + 24]
    jne .Lfail_decode
    mov rax, [rip + .Lposition]
    cmp rax, [r12 + 32]
    jne .Lfail_decode
    add r12, 40
    cmp r12, r13
    jne .Lcheck_decode

    lea r12, [rip + .Lencode_cases]
    lea r13, [rip + .Lencode_end]
.Lcheck_encode:
    mov dword ptr [rip + .Lencoded], 0xaaaaaaaa
    lea rdi, [rip + .Lencoded]
    mov esi, [r12]
    call _ZN4lean19push_unicode_scalarEPcj
    cmp eax, [r12 + 4]
    jne .Lfail_encode
    mov eax, [rip + .Lencoded]
    cmp eax, [r12 + 8]
    jne .Lfail_encode
    add r12, 12
    cmp r12, r13
    jne .Lcheck_encode
    xor edi, edi
    jmp .Lexit
.Lfail_width:
    mov edi, 1
    jmp .Lexit
.Lfail_cont:
    mov edi, 2
    jmp .Lexit
.Lfail_strlen:
    mov edi, 3
    jmp .Lexit
.Lfail_last:
    mov edi, 4
    jmp .Lexit
.Lfail_validate:
    mov edi, 5
    jmp .Lexit
.Lfail_decode:
    mov edi, 6
    jmp .Lexit
.Lfail_encode:
    mov edi, 7
.Lexit:
    mov eax, 60
    syscall
.size _start, . - _start

.section .note.GNU-stack,"",@progbits
