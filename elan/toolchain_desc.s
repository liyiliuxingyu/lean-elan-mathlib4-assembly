# SPDX-License-Identifier: Apache-2.0 OR MIT
# Assembly translation of the Elan v4.2.4 descriptor operations in
# src/elan-dist/src/dist.rs. See README.md for the source pin and ABI.
.intel_syntax noprefix

.equ DESC_KIND, 0
.equ DESC_FIRST_PTR, 8
.equ DESC_FIRST_LEN, 16
.equ DESC_SECOND_PTR, 24
.equ DESC_SECOND_LEN, 32

.text
.globl elan_parse_resolved
.type elan_parse_resolved, @function
# (input, length, out) -> kind
# Kinds are invalid=0, local=1, remote=2, path=3.
elan_parse_resolved:
    xor eax, eax
    mov [rdx + DESC_KIND], rax
    mov [rdx + DESC_FIRST_PTR], rax
    mov [rdx + DESC_FIRST_LEN], rax
    mov [rdx + DESC_SECOND_PTR], rax
    mov [rdx + DESC_SECOND_LEN], rax

    test rsi, rsi
    jz .Lparse_done
    cmp BYTE PTR [rdi], '/'
    je .Lpath

    xor r8d, r8d            # Current input offset.
    xor r9d, r9d            # Offset just after the owner separator, or zero.
    xor r10d, r10d          # Offset just after the release separator, or zero.
    xor r11d, r11d          # A dot in the candidate local name.
    xor ecx, ecx            # An underscore in the candidate origin.

.Lparse_byte:
    movzx eax, BYTE PTR [rdi + r8]
    cmp al, '-'
    je .Ladvance
    cmp al, '.'
    je .Ldot
    cmp al, '_'
    je .Lunderscore
    cmp al, '/'
    je .Lslash
    cmp al, ':'
    je .Lcolon
    cmp al, '0'
    jb .Linvalid
    cmp al, '9'
    jbe .Ladvance
    or al, 0x20
    cmp al, 'a'
    jb .Linvalid
    cmp al, 'z'
    ja .Linvalid

.Ladvance:
    inc r8
    cmp r8, rsi
    jb .Lparse_byte
    test r10, r10
    jnz .Lremote
    test r9, r9
    jnz .Linvalid
    test ecx, ecx
    jnz .Linvalid
    mov eax, 1
    jmp .Lone_slice

.Ldot:
    test r10, r10           # Release bytes after the colon may contain dots.
    jnz .Ladvance
    test r9, r9
    jnz .Linvalid          # The repository part may not contain dots.
    mov r11d, 1
    jmp .Ladvance

.Lunderscore:
    test r10, r10
    jnz .Linvalid
    mov ecx, 1
    jmp .Ladvance

.Lslash:
    test r9, r9
    jnz .Linvalid
    test r11d, r11d
    jnz .Linvalid          # The owner part may not contain dots.
    # A leading slash was already recognized as an absolute path.
    lea r9, [r8 + 1]
    jmp .Ladvance

.Lcolon:
    test r9, r9
    jz .Linvalid
    test r10, r10
    jnz .Linvalid
    cmp r8, r9             # The repository part must be nonempty.
    je .Linvalid
    lea r10, [r8 + 1]
    jmp .Ladvance

.Lremote:
    cmp r10, rsi            # The release must be nonempty.
    je .Linvalid
    lea r8, [r10 - 1]
    mov [rdx + DESC_FIRST_PTR], rdi
    mov [rdx + DESC_FIRST_LEN], r8
    lea r8, [rdi + r10]
    sub rsi, r10
    mov [rdx + DESC_SECOND_PTR], r8
    mov [rdx + DESC_SECOND_LEN], rsi
    mov eax, 2
    jmp .Lstore_kind

.Lpath:
    mov eax, 3
.Lone_slice:
    mov [rdx + DESC_FIRST_PTR], rdi
    mov [rdx + DESC_FIRST_LEN], rsi
.Lstore_kind:
    mov [rdx + DESC_KIND], rax
.Lparse_done:
    ret

.Linvalid:
    xor eax, eax
    ret
.size elan_parse_resolved, .-elan_parse_resolved

.globl elan_decode_toolchain_dir
.type elan_decode_toolchain_dir, @function
# (input, length, buffer, capacity) -> decoded length, or -1 if full.
# Input and output can have the same start address.
elan_decode_toolchain_dir:
    xor eax, eax
    test rsi, rsi
    jz .Ldecode_done

.Ldecode_byte:
    cmp rax, rcx
    jae .Lbuffer_full
    mov r8b, BYTE PTR [rdi]
    cmp r8b, '-'
    jne .Lemit_one
    cmp rsi, 2
    jb .Lemit_one
    cmp BYTE PTR [rdi + 1], '-'
    jne .Lemit_one
    cmp rsi, 3
    jb .Lemit_slash
    cmp BYTE PTR [rdi + 2], '-'
    jne .Lemit_slash
    # Replace triples before pairs, matching the two upstream passes.
    add rdi, 2
    sub rsi, 2
    mov r8b, ':'
    jmp .Lemit_one

.Lemit_slash:
    inc rdi
    dec rsi
    mov r8b, '/'

.Lemit_one:
    mov BYTE PTR [rdx + rax], r8b
    inc rax
    inc rdi
    dec rsi
    jnz .Ldecode_byte

.Ldecode_done:
    ret

.Lbuffer_full:
    mov rax, -1
    ret
.size elan_decode_toolchain_dir, .-elan_decode_toolchain_dir

.globl elan_parse_toolchain_dir
.type elan_parse_toolchain_dir, @function
# (input, length, buffer, capacity, out) -> kind, or -1 if full.
elan_parse_toolchain_dir:
    push r8
    push rdx
    sub rsp, 8
    call elan_decode_toolchain_dir
    add rsp, 8
    pop rdi
    pop rdx
    test rax, rax
    js .Ldir_done
    mov rsi, rax
    jmp elan_parse_resolved

.Ldir_done:
    ret
.size elan_parse_toolchain_dir, .-elan_parse_toolchain_dir

.section .note.GNU-stack,"",@progbits
