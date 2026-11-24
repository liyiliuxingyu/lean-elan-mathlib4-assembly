# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "olean_layout.inc"

.equ TERM_HEADER_BYTES, 96
.equ TERM_STRING_TAG, 249
.equ TERM_MPZ_TAG, 250

.section .rodata
.Lhex:
    .ascii "0123456789abcdef"
.Lanonymous:
    .asciz "[anonymous]"

.text
# rdi: parsed view, rax: serialized pointer (or file offset at .Loffset_ptr).
# r8: minimum bytes. rax: mapped pointer or zero. Clobbers rcx.
.Lraw_ptr:
    sub rax, [rdi + VIEW_BASE]
    jc .Lbad_ptr
.Loffset_ptr:
    cmp rax, TERM_HEADER_BYTES
    jb .Lbad_ptr
    test al, 7
    jnz .Lbad_ptr
    mov rcx, [rdi + VIEW_SIZE]
    sub rcx, r8
    jc .Lbad_ptr
    cmp rax, rcx
    ja .Lbad_ptr
    add rax, [rdi + VIEW_MAPPING]
    ret
.Lbad_ptr:
    xor eax, eax
    ret

# rdi: view, rax: serialized String. rax: bytes or zero. rdx:
# byte length excluding NUL on success. String length is checked independently
# of the cached character count.
.Lstring_bytes:
    mov r8d, 32
    call .Lraw_ptr
    test rax, rax
    jz .Lbad_ptr
    cmp word ptr [rax + 6], TERM_STRING_TAG << 8
    jne .Lbad_ptr
    mov rdx, [rax + 8]
    test rdx, rdx
    jz .Lbad_ptr
    cmp rdx, [rax + 16]
    jne .Lbad_ptr
    lea rax, [rax + 32]
    mov rcx, [rdi + VIEW_MAPPING]
    add rcx, [rdi + VIEW_SIZE]
    sub rcx, rax
    cmp rdx, rcx
    ja .Lbad_ptr
    dec rdx
    cmp byte ptr [rax + rdx], 0
    jne .Lbad_ptr
    ret

# rdi: output beginning, rsi: first character, rdx: final NUL.
# Move the name or literal from the buffer tail to its beginning.
.Lfinish_format:
    mov rax, rdx
    sub rax, rsi
    lea rcx, [rax + 1]
    rep movsb
    ret

# rdi: buffer beginning, rsi: cursor, eax: byte to escape.
# Return updated cursor in rsi, or zero on insufficient room.
# Build a textual ASCII escape from a raw byte without emitting TSV controls.
.Lhex_byte:
    mov rcx, rsi
    sub rcx, rdi
    cmp rcx, 4
    jb .Lhex_no_room
    lea rcx, [rip + .Lhex]
    sub rsi, 4
    mov word ptr [rsi], 0x785c      # backslash-x, in little-endian
    mov edx, eax
    and eax, 15
    shr edx, 4
    mov al, [rcx + rax]
    mov dl, [rcx + rdx]
    mov [rsi + 2], dl
    mov [rsi + 3], al
    ret
.Lhex_no_room:
    xor esi, esi
    ret

.globl mathlib_olean_name_format
.type mathlib_olean_name_format, @function
# view, serialized Name (or boxed anonymous 1), output, output capacity.
# Return byte count excluding NUL, or -1 on invalid data or short output.
# Names use dotted components, with guillemets for nonidentifier components
# and byte escapes for controls, backslashes or literal guillemets.
mathlib_olean_name_format:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test rcx, rcx
    jz .Lname_error
    cmp rcx, 0x7fffffff
    ja .Lname_error
    mov r15, r14
    add r15, rcx
    jc .Lname_error
    dec r15
    mov rbx, r15
    mov byte ptr [r15], 0
    cmp r13, 1
    jne .Lname_component
    cmp rcx, 12                    # 11-byte marker and NUL
    jb .Lname_error
    mov rdi, r14
    lea rsi, [rip + .Lanonymous]
    mov ecx, 12
    rep movsb
    mov eax, 11
    jmp .Lname_return

.Lname_component:
    mov rdi, r12
    mov rax, r13
    mov r8d, 32
    call .Lraw_ptr
    test rax, rax
    jz .Lname_error
    cmp word ptr [rax + 4], 32
    jne .Lname_error
    cmp r13, [rax + 8]
    je .Lname_error
    mov r13, [rax + 8]
    cmp word ptr [rax + 6], 0x0202
    je .Lnumerical_name
    cmp word ptr [rax + 6], 0x0102
    jne .Lname_error
    mov rax, [rax + 16]
    call .Lstring_bytes
    test rax, rax
    jz .Lname_error

    # Keep simple ASCII identifiers unquoted, otherwise quote a component.
    # Non-ASCII bytes are preserved inside quotes to retain the UTF-8 name.
    test rdx, rdx
    jz .Lname_quote
    xor r8d, r8d
.Lname_check_ident:
    movzx ecx, byte ptr [rax + r8]
    cmp cl, '_'
    je .Lname_ident_next
    mov r9d, ecx
    or r9b, 32
    sub r9d, 'a'
    cmp r9d, 25
    jbe .Lname_ident_next
    test r8, r8
    jz .Lname_quote
    cmp cl, 39
    je .Lname_ident_next
    sub ecx, '0'
    cmp ecx, 9
    ja .Lname_quote
.Lname_ident_next:
    inc r8
    cmp r8, rdx
    jb .Lname_check_ident
    mov rcx, r15
    sub rcx, r14
    cmp rdx, rcx
    ja .Lname_error
    sub r15, rdx
    mov rdi, r15
    mov rsi, rax
    mov rcx, rdx
    rep movsb
    jmp .Lname_prefix

.Lname_quote:
    mov r9, rax                    # string start
    lea r10, [rax + rdx]           # next byte from the right
    mov rcx, r15
    sub rcx, r14
    cmp rcx, 4                    # both guillemets
    jb .Lname_error
    sub r15, 2
    mov word ptr [r15], 0xbbc2
.Lname_quoted_byte:
    cmp r10, r9
    je .Lname_open_quote
    dec r10
    movzx eax, byte ptr [r10]
    cmp al, 32
    jb .Lname_escape
    cmp al, 127
    je .Lname_escape
    cmp al, 92
    je .Lname_escape
    cmp al, 0xab
    je .Lname_maybe_guillemet
    cmp al, 0xbb
    jne .Lname_copy_byte
.Lname_maybe_guillemet:
    cmp r10, r9
    je .Lname_copy_byte
    cmp byte ptr [r10 - 1], 0xc2
    jne .Lname_copy_byte
    mov rdi, r14
    mov rsi, r15
    call .Lhex_byte
    test rsi, rsi
    jz .Lname_error
    mov r15, rsi
    dec r10
    mov eax, 0xc2
.Lname_escape:
    mov rdi, r14
    mov rsi, r15
    call .Lhex_byte
    test rsi, rsi
    jz .Lname_error
    mov r15, rsi
    jmp .Lname_quoted_byte
.Lname_copy_byte:
    cmp r15, r14
    je .Lname_error
    dec r15
    mov [r15], al
    jmp .Lname_quoted_byte
.Lname_open_quote:
    mov rcx, r15
    sub rcx, r14
    cmp rcx, 2
    jb .Lname_error
    sub r15, 2
    mov word ptr [r15], 0xabc2
    jmp .Lname_prefix

.Lnumerical_name:
    mov rdi, r12
    mov rsi, [rax + 16]
    mov rdx, r14
    mov rcx, r15
    call .Lprepend_nat
    test rax, rax
    jz .Lname_error
    mov r15, rax
.Lname_prefix:
    cmp r13, 1
    je .Lname_done
    cmp r15, r14
    je .Lname_error
    dec r15
    mov byte ptr [r15], '.'
    jmp .Lname_component
.Lname_done:
    mov rdi, r14
    mov rsi, r15
    mov rdx, rbx
    call .Lfinish_format
    jmp .Lname_return
.Lname_error:
    mov eax, -1
.Lname_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size mathlib_olean_name_format, .-mathlib_olean_name_format

.globl mathlib_olean_string_format
.type mathlib_olean_string_format, @function
# view, serialized String, output, output capacity. Return byte count
# excluding NUL or -1. Literal strings are enclosed in double quotes.
mathlib_olean_string_format:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdx
    cmp rcx, 3
    jb .Lstring_error
    cmp rcx, 0x7fffffff
    ja .Lstring_error
    mov r13, r12
    add r13, rcx
    jc .Lstring_error
    dec r13
    lea r14, [r13 - 1]
    mov byte ptr [r13], 0
    mov byte ptr [r14], 34
    mov rax, rsi
    call .Lstring_bytes
    test rax, rax
    jz .Lstring_error
    mov r15, rax
    lea r9, [rax + rdx]
.Lliteral_byte:
    cmp r9, r15
    je .Lliteral_start_quote
    dec r9
    movzx eax, byte ptr [r9]
    cmp al, 32
    jb .Lliteral_escape
    cmp al, 127
    je .Lliteral_escape
    cmp al, 34
    je .Lliteral_escape
    cmp al, 92
    je .Lliteral_escape
    cmp r14, r12
    je .Lstring_error
    dec r14
    mov [r14], al
    jmp .Lliteral_byte
.Lliteral_escape:
    mov rdi, r12
    mov rsi, r14
    call .Lhex_byte
    test rsi, rsi
    jz .Lstring_error
    mov r14, rsi
    jmp .Lliteral_byte
.Lliteral_start_quote:
    cmp r14, r12
    je .Lstring_error
    dec r14
    mov byte ptr [r14], 34
    mov rdi, r12
    mov rsi, r14
    mov rdx, r13
    call .Lfinish_format
    jmp .Lstring_return
.Lstring_error:
    mov eax, -1
.Lstring_return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.size mathlib_olean_string_format, .-mathlib_olean_string_format

.globl mathlib_olean_nat_format
.type mathlib_olean_nat_format, @function
# view, serialized Nat (boxed immediate or GMP object), output, capacity.
# Return byte count excluding NUL or -1.
mathlib_olean_nat_format:
    push r12
    push r13
    sub rsp, 8
    test rcx, rcx
    jz .Lnat_error
    cmp rcx, 0x7fffffff
    ja .Lnat_error
    mov r12, rdx
    add rcx, rdx
    jc .Lnat_error
    dec rcx
    mov r13, rcx
    mov byte ptr [r13], 0
    call .Lprepend_nat
    test rax, rax
    jz .Lnat_error
    mov rdi, r12
    mov rsi, rax
    mov rdx, r13
    call .Lfinish_format
    jmp .Lnat_return
.Lnat_error:
    mov eax, -1
.Lnat_return:
    add rsp, 8
    pop r13
    pop r12
    ret
.size mathlib_olean_nat_format, .-mathlib_olean_nat_format

# Prepend decimal digits right-to-left. rdi=view, rsi=serialized Nat,
# rdx=beginning, rcx=cursor. New cursor or zero in rax.
.Lprepend_nat:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbp, rsp
    mov r12, rdx
    mov r13, rcx
    test sil, 1
    jz .Lbig_nat
    mov rax, rsi
    shr rax, 1
    xor r15d, r15d
    jmp .Lnat_digits

.Lbig_nat:
    mov r14, rsi
    mov rax, rsi
    mov r8d, 24
    call .Lraw_ptr
    test rax, rax
    jz .Lprepend_nat_bad
    cmp word ptr [rax + 6], TERM_MPZ_TAG << 8
    jne .Lprepend_nat_bad
    mov r15d, [rax + 12]            # GMP signed limb count
    test r15d, r15d
    jle .Lprepend_nat_bad
    cmp r15d, [rax + 8]             # pinned compactor writes exact capacity
    jne .Lprepend_nat_bad
    lea r8, [r15 * 8 + 24]
    cmp r8, 65535
    ja .Lprepend_nat_bad
    cmp [rax + 4], r8w
    jne .Lprepend_nat_bad
    mov rax, r14
    call .Lraw_ptr
    test rax, rax
    jz .Lprepend_nat_bad
    add r14, 24
    jc .Lprepend_nat_bad
    cmp [rax + 16], r14             # serialized limb pointer, inline data
    jne .Lprepend_nat_bad
    cmp qword ptr [rax + r15 * 8 + 16], 0
    je .Lprepend_nat_bad

    # At least 19*(n-1)+1 decimal digits. Check before allocating scratch
    # so a tiny destination does not incur big conversion costs.
    lea rcx, [r15 - 1]
    imul rcx, 19
    inc rcx
    mov rdx, r13
    sub rdx, r12
    cmp rcx, rdx
    ja .Lprepend_nat_bad
    lea rcx, [r15 * 8 + 15]
    and rcx, -16
    sub rsp, rcx
    mov rdi, rsp
    lea rsi, [rax + 24]
    mov rcx, r15
    rep movsq
    movabs rbx, 10000000000000000000
.Lnat_chunk:
    xor edx, edx
    mov rcx, r15
.Lnat_divide:
    dec rcx
    mov rax, [rsp + rcx * 8]
    div rbx
    mov [rsp + rcx * 8], rax
    test rcx, rcx
    jnz .Lnat_divide
.Lnat_trim:
    test r15, r15
    jz .Lnat_chunk_digits
    cmp qword ptr [rsp + r15 * 8 - 8], 0
    jne .Lnat_chunk_digits
    dec r15
    jmp .Lnat_trim
.Lnat_chunk_digits:
    mov rax, rdx
.Lnat_digits:
    mov r8d, 10
    mov ecx, 19
.Lnext_nat_digit:
    cmp r13, r12
    je .Lprepend_nat_bad
    xor edx, edx
    div r8
    add dl, '0'
    dec r13
    mov [r13], dl
    dec ecx
    test ecx, ecx
    jz .Lnext_nat_chunk
    test r15, r15
    jnz .Lnext_nat_digit
    test rax, rax
    jnz .Lnext_nat_digit
.Lnext_nat_chunk:
    test r15, r15
    jnz .Lnat_chunk
    mov rax, r13
    jmp .Lprepend_nat_done
.Lprepend_nat_bad:
    xor eax, eax
.Lprepend_nat_done:
    mov rsp, rbp
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.globl mathlib_olean_level_node
.type mathlib_olean_level_node, @function
# view, Level file offset (boxed 1 for .zero), result four qwords.
# Output: tag, first child file offset or raw Name (parameter/metavariable),
# second child file offset, zero. Immediate child .zero is returned as 1.
# Return 1 on success, 0 on invalid layout. On failure output is unspecified.
mathlib_olean_level_node:
    xor r9d, r9d
    xor r10d, r10d
    xor r11d, r11d
    mov r8, rdx
    cmp rsi, 1
    je .Llevel_result
    mov rax, rsi
    mov r8d, 8
    call .Loffset_ptr
    test rax, rax
    jz .Llevel_error
    movzx r9d, byte ptr [rax + 7]
    cmp r9d, 1
    jb .Llevel_error
    cmp r9d, 5
    ja .Llevel_error
    mov r8d, 24
    cmp r9d, 2
    je .Llevel_two
    cmp r9d, 3
    je .Llevel_two
    cmp byte ptr [rax + 6], 1
    jne .Llevel_error
    jmp .Llevel_size
.Llevel_two:
    cmp byte ptr [rax + 6], 2
    jne .Llevel_error
    mov r8d, 32
.Llevel_size:
    cmp [rax + 4], r8w
    jne .Llevel_error
    mov rax, rsi
    call .Loffset_ptr
    test rax, rax
    jz .Llevel_error
    mov r10, [rax + 8]
    cmp r9d, 4
    jae .Llevel_name
    cmp r8d, 32
    jne .Llevel_child
    mov r11, [rax + 16]
    cmp r11, 1
    je .Llevel_child
    sub r11, [rdi + VIEW_BASE]
    jc .Llevel_error
    mov rax, r11
    mov r8d, 8
    call .Loffset_ptr
    test rax, rax
    jz .Llevel_error
.Llevel_child:
    cmp r10, 1
    je .Llevel_store
    sub r10, [rdi + VIEW_BASE]
    jc .Llevel_error
    mov rax, r10
    mov r8d, 8
    call .Loffset_ptr
    test rax, rax
    jz .Llevel_error
    jmp .Llevel_store
.Llevel_name:
    cmp r10, 1
    je .Llevel_store
    mov rax, r10
    mov r8d, 32
    call .Lraw_ptr
    test rax, rax
    jz .Llevel_error
    cmp word ptr [rax + 6], 0x0102
    je .Llevel_store
    cmp word ptr [rax + 6], 0x0202
    jne .Llevel_error
.Llevel_store:
    mov r8, rdx
.Llevel_result:
    mov [r8], r9
    mov [r8 + 8], r10
    mov [r8 + 16], r11
    mov qword ptr [r8 + 24], 0
    mov eax, 1
    ret
.Llevel_error:
    xor eax, eax
    ret
.size mathlib_olean_level_node, .-mathlib_olean_level_node

.section .note.GNU-stack,"",@progbits
