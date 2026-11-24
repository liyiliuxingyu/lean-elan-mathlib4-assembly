/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Elan 4.2.4's utils::toolchain_sort orders semver 0.11 Version values.
 * Given a validated, decoded toolchain descriptor, write an order-preserving
 * binary key. Unsigned components use eight big-endian bytes. A release
 * follows its prereleases. Each prerelease identifier carries a type tag,
 * and an end-of-list tag sorts before another identifier.
 *
 * rdi = NUL-terminated name; rsi = destination (10 * name length + 64
 * bytes suffice); rax = key length. Build metadata and underscores can never
 * occur in a numeric-leading, validated local descriptor.
 */
.intel_syntax noprefix
.text
.globl elan_toolchain_order_key
.type elan_toolchain_order_key,@function
elan_toolchain_order_key:
    push rbx
    push r12
    push r13
    mov r12, rdi                    /* original name */
    mov r13, rsi                    /* start of output */
    mov rdi, rsi
    mov rsi, r12
    mov ebx, 3
    lea r8, [rip+.Lprefixes]
    xor edx, edx
.Lprefix:
    mov rax, [r8+rdx*8]
    xor ecx, ecx
.Lmatch:
    mov r9b, [rax+rcx]
    test r9b, r9b
    jz .Lchannel
    cmp [r12+rcx], r9b
    jne .Lnext_prefix
    inc ecx
    jmp .Lmatch
.Lnext_prefix:
    inc edx
    cmp edx, 3
    jb .Lprefix

    mov r8d, 3                     /* major.minor.patch */
.Lcore:
    mov r9, rsi
.Lcore_digit:
    movzx eax, byte ptr [rsi]
    sub eax, '0'
    cmp eax, 9
    ja .Lcore_end
    inc rsi
    jmp .Lcore_digit
.Lcore_end:
    call .Lparse_numeric           /* [r9,rsi) -> unsigned u64 */
    jc .Lspecial
    bswap rax
    stosq
    dec r8d
    jz .Lafter_core
    cmp byte ptr [rsi], '.'
    jne .Lspecial
    inc rsi
    jmp .Lcore
.Lafter_core:
    mov al, 1                      /* ordinary release */
    cmp byte ptr [rsi], 0
    je .Lend_key
    cmp byte ptr [rsi], '-'
    jne .Lspecial
    xor eax, eax                   /* prerelease */
    stosb
.Lidentifier:
    inc rsi                        /* past '-' or '.' */
    mov r9, rsi
.Lsegment:
    mov rcx, rsi
.Lalnum:
    movzx eax, byte ptr [rsi]
    sub al, '0'
    cmp al, 9
    jbe .Lconsume
    mov al, [rsi]
    or al, 32
    sub al, 'a'
    cmp al, 25
    ja .Lsegment_end
.Lconsume:
    inc rsi
    jmp .Lalnum
.Lsegment_end:
    cmp rsi, rcx                   /* leading, trailing, or repeated separator */
    je .Lspecial
    cmp byte ptr [rsi], '-'
    jne .Lemit_id
    inc rsi
    jmp .Lsegment
.Lemit_id:
    call .Lparse_numeric
    jc .Lalpha
    mov byte ptr [rdi], 1
    inc rdi
    bswap rax
    stosq
    jmp .Lnext_id
.Lalpha:
    mov al, 2
    stosb
    mov rcx, rsi
    sub rcx, r9
    mov rsi, r9
    rep movsb
    xor eax, eax
    stosb
.Lnext_id:
    cmp byte ptr [rsi], '.'
    je .Lidentifier
    cmp byte ptr [rsi], 0
    jne .Lspecial
    xor eax, eax                   /* end of identifier vector */
    jmp .Lend_key

.Lchannel:
    mov ebx, edx
.Lspecial:
    mov rdi, r13
    xor eax, eax                   /* 0.0.0-<rank>.<name> */
    stosq
    stosq
    stosq
    stosb
    inc eax
    stosb
    mov eax, ebx
    bswap rax
    stosq
    mov al, 2
    stosb
    mov rsi, r12
.Lwhole_name:
    lodsb
    stosb
    test al, al
    jnz .Lwhole_name
.Lend_key:
    stosb
    mov rax, rdi
    sub rax, r13
    pop r13
    pop r12
    pop rbx
    ret

/* Semver classifies digits with a leading zero or u64 overflow as a string
 * identifier. The core requires numeric tokens, so those cases invalidate it. */
.Lparse_numeric:
    cmp r9, rsi
    je .Lnot_numeric
    cmp byte ptr [r9], '0'
    jne .Ldigits
    lea rax, [r9+1]
    cmp rax, rsi
    jne .Lnot_numeric
.Ldigits:
    mov r10, r9
    xor eax, eax
    mov r11d, 10
.Ldigit:
    movzx ecx, byte ptr [r10]
    sub ecx, '0'
    cmp ecx, 9
    ja .Lnot_numeric
    mul r11
    jc .Lnot_numeric
    add rax, rcx
    jc .Lnot_numeric
    inc r10
    cmp r10, rsi
    jb .Ldigit
    clc
    ret
.Lnot_numeric:
    stc
    ret
.size elan_toolchain_order_key, .-elan_toolchain_order_key
.section .rodata
.Lstable: .asciz "stable"
.Lbeta: .asciz "beta"
.Lnightly: .asciz "nightly"
.balign 8
.Lprefixes: .quad .Lstable, .Lbeta, .Lnightly
.section .note.GNU-stack,"",@progbits
