# SPDX-License-Identifier: Apache-2.0
# Canonical declaration and query keys. All integer fields are little-endian.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ PART_BYTES, QUERY_BYTES - QUERY_COMPONENTS
.equ RECORD,     PART_BYTES
.equ DEST,       RECORD + RESULT_BYTES
.equ CAPACITY,   DEST + 8
.equ KIND_OUT,   CAPACITY + 8
.equ REMAINING,  KIND_OUT + 8
.equ RAW_NAT,    REMAINING + 8
.equ FRAME,      RAW_NAT + 8

.text
.globl catalog_key_query
.type catalog_key_query,@function
# (NUL-terminated name, output, capacity) -> signed length, -1 or -2.
catalog_key_query:
    test rdi, rdi
    jz .Linvalid
    push r12
    push r13
    sub rsp, QUERY_BYTES
    mov r12, rsi
    mov r13, rdx
    mov rsi, rsp
    call mathlib_olean_parse_query
    test eax, eax
    jz .Lquery_bad
    mov rdi, rsp
    mov esi, eax
    mov rdx, r12
    mov rcx, r13
    call .Lencode
    jmp .Lquery_done
.Lquery_bad:
    mov rax, -1
.Lquery_done:
    add rsp, QUERY_BYTES
    pop r13
    pop r12
    ret
.size catalog_key_query, .-catalog_key_query

.globl catalog_key_decl
.type catalog_key_decl,@function
# (parsed view, declaration index, output, capacity, uint64_t *kind) -> length.
# -1 malformed or invalid argument, -2 no room, -3 outside query grammar.
# Both output arguments are written only on success. NULL,0 asks for length.
catalog_key_decl:
    test rdi, rdi
    jz .Linvalid
    test r8, r8
    jz .Linvalid
    cmp rsi, [rdi + VIEW_COUNT]
    jae .Linvalid
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME
    mov r12, rdi
    mov [rsp + DEST], rdx
    mov [rsp + CAPACITY], rcx
    mov [rsp + KIND_OUT], r8
    mov rax, [rdi + VIEW_NAMES]
    mov r13, [rax + rsi*8]
    lea rdx, [rsp + RECORD]
    call mathlib_olean_record
    cmp eax, 1
    jne .Ldecl_bad

    cmp r13, 1                       # The query parser requires one component.
    je .Lunqueryable
    lea r14, [rsp + PART_BYTES]      # Fill from the end, reversing the chain.
    xor r15d, r15d                   # Set if the name exceeds query limits.
    mov rbp, r13                     # Brent cycle detection for all depths.
    mov ebx, 1                       # Current power-of-two interval.
    mov [rsp + REMAINING], rbx
.Lname:
    mov rdi, r12
    mov rsi, r13
    mov edx, 32
    call mathlib_olean_object
    test rax, rax
    jz .Ldecl_bad
    mov r13, [rax + 8]               # Prefix, including Name.anonymous.
    movzx ecx, word ptr [rax + 6]
    mov rsi, [rax + 16]
    cmp ecx, 0x0202                  # Name.num
    je .Lnumber
    cmp ecx, 0x0102                  # Name.str
    jne .Ldecl_bad
    mov rdi, r12
    mov edx, 32
    call mathlib_olean_object
    test rax, rax
    jz .Ldecl_bad
    cmp word ptr [rax + 6], 249 << 8 # LeanString
    jne .Ldecl_bad
    mov rdx, [rax + 8]
    test rdx, rdx
    jz .Ldecl_bad
    cmp rdx, [rax + 16]              # Compacted strings have exact capacity.
    jne .Ldecl_bad
    lea rsi, [rax + 32]
    mov rcx, [r12 + VIEW_MAPPING]
    add rcx, [r12 + VIEW_SIZE]
    sub rcx, rsi
    cmp rdx, rcx
    ja .Ldecl_bad
    dec rdx
    cmp byte ptr [rsi + rdx], 0
    jne .Ldecl_bad
    # Quoted parts admit an empty string, spaces, DEL, and U+00AB. In both
    # accepted spellings, control bytes and a literal closing U+00BB cannot
    # occur inside a component. Still check the rest of the prefix chain.
    xor ecx, ecx
.Lstring_byte:
    cmp rcx, rdx
    jae .Lpart
    movzx eax, byte ptr [rsi + rcx]
    cmp al, 0x20
    jb .Lmark_unqueryable
    cmp al, 0xc2
    jne .Lnext_byte
    cmp byte ptr [rsi + rcx + 1], 0xbb
    je .Lmark_unqueryable
.Lnext_byte:
    inc rcx
    jmp .Lstring_byte
.Lnumber:
    test sil, 1
    jz .Lheap_nat
    mov rdx, -1
.Lpart:
    cmp r14, rsp
    je .Lmark_unqueryable
    sub r14, 16
    mov [r14], rsi
    mov [r14 + 8], rdx
    jmp .Lprefix

.Lheap_nat:
    # The parser accepts immediate Nat indices. Validate the compact positive
    # GMP object and its inline limbs before classifying this name as skipped.
    mov [rsp + RAW_NAT], rsi
    mov rdi, r12
    mov edx, 24
    call mathlib_olean_object
    test rax, rax
    jz .Ldecl_bad
    cmp word ptr [rax + 6], 250 << 8
    jne .Ldecl_bad
    mov ecx, [rax + 12]
    test ecx, ecx
    jle .Ldecl_bad
    cmp ecx, [rax + 8]
    jne .Ldecl_bad
    lea rdx, [rcx*8 + 24]
    cmp dx, [rax + 4]                # m_cs_sz stores only the low 16 bits.
    jne .Ldecl_bad
    mov rsi, [rsp + RAW_NAT]
    mov rcx, rsi
    add rcx, 24
    jc .Ldecl_bad
    cmp rcx, [rax + 16]
    jne .Ldecl_bad
    mov rdi, r12
    call mathlib_olean_object
    test rax, rax
    jz .Ldecl_bad
    mov ecx, [rax + 12]
    cmp qword ptr [rax + rcx*8 + 16], 0
    je .Ldecl_bad
.Lmark_unqueryable:
    mov r15d, 1
.Lprefix:
    cmp r13, 1
    je .Lname_done
    cmp r13, rbp
    je .Ldecl_bad
    dec qword ptr [rsp + REMAINING]
    jnz .Lname
    mov rbp, r13
    add rbx, rbx
    mov [rsp + REMAINING], rbx
    jmp .Lname

.Lname_done:
    test r15d, r15d
    jnz .Lunqueryable
    mov rdi, r14
    lea rsi, [rsp + PART_BYTES]
    sub rsi, r14
    shr esi, 4
    mov rdx, [rsp + DEST]
    mov rcx, [rsp + CAPACITY]
    call .Lencode
    test rax, rax
    js .Ldecl_done
    mov rcx, [rsp + KIND_OUT]
    mov rdx, [rsp + RECORD + RESULT_KIND]
    mov [rcx], rdx
    jmp .Ldecl_done
.Lunqueryable:
    mov rax, -3
    jmp .Ldecl_done
.Ldecl_bad:
    mov rax, -1
.Ldecl_done:
    add rsp, FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.size catalog_key_decl, .-catalog_key_decl

# Encode the same (data/boxed Nat, length/-1) pairs for both inputs.
# First calculate the entire size. A capacity error leaves the buffer intact.
.Lencode:
    mov r8, rdi
    shl esi, 4
    lea r9, [rdi + rsi]
    xor r11d, r11d
.Lmeasure:
    add r11, 9                       # 1-byte tag and 8-byte length or value.
    jo .Linvalid
    mov rax, [rdi + 8]
    cmp rax, -1
    je .Lmeasured_part
    add r11, rax
    jo .Linvalid
.Lmeasured_part:
    add rdi, 16
    cmp rdi, r9
    jb .Lmeasure
    test rdx, rdx
    jnz .Lbuffer
    test rcx, rcx
    jnz .Linvalid
    jmp .Ldone
.Lbuffer:
    cmp rcx, r11
    jb .Lno_room
    mov rax, rdx
    add rax, r11
    jc .Linvalid
    mov rdi, rdx
.Lemit:
    mov rsi, [r8]
    mov rcx, [r8 + 8]
    cmp rcx, -1
    je .Lemit_number
    mov byte ptr [rdi], 1
    mov [rdi + 1], rcx
    add rdi, 9
    rep movsb
    jmp .Lemitted
.Lemit_number:
    mov byte ptr [rdi], 2
    shr rsi, 1                       # Canonical unboxed index.
    mov [rdi + 1], rsi
    add rdi, 9
.Lemitted:
    add r8, 16
    cmp r8, r9
    jb .Lemit
.Ldone:
    mov rax, r11
    ret
.Lno_room:
    mov rax, -2
    ret
.Linvalid:
    mov rax, -1
    ret

.section .note.GNU-stack,"",@progbits
