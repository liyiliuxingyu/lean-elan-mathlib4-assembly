/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Local subset of Elan 4.2.4 config.rs: find [package].lean_version.
 *
 * SysV rdi = mutable, NUL-terminated UTF-8 text (caller rejects embedded
 * NUL). rax = decoded string, zero if absent, or -1 if invalid/unsupported.
 * One-component TOML table names and assignment keys can be bare or quoted.
 * Accept single-line strings, booleans, decimal i64 without underscores, and
 * flat inline tables of these scalars, including package = {lean_version=...}.
 * A document may contain up to 2048 keys and table headers in total.
 */
.intel_syntax noprefix
.equ KEY_LIMIT, 2048
.equ FRAME_BYTES, KEY_LIMIT*16+40
.section .text
.globl elan_leanpkg_version
.type elan_leanpkg_version, @function
elan_leanpkg_version:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, FRAME_BYTES
    lea rbp, [rsp+32]             /* (owner, decoded key) pairs */
    mov r12, rdi                  /* cursor into original text */
    xor r13d, r13d                /* current table; zero is document root */
    xor r14d, r14d                /* result */
    xor r15d, r15d                /* used entries */
    mov qword ptr [rsp+8], 0      /* inside an inline table */
    mov qword ptr [rsp+16], 0     /* identity of root package table */
.Lline:
    call .Lspace
    test al, al
    jz .Lsuccess
    cmp al, '#'
    je .Lcomment
    cmp al, 10
    je .Lnewline
    cmp al, 13
    je .Lcrlf
    cmp al, '['
    jne .Lassignment
    inc r12
    call .Lkey
    jc .Lbad
    call .Lspace
    cmp al, ']'
    jne .Lbad
    inc r12
    mov byte ptr [rsi], 0
    xor edx, edx                  /* headers declare keys at document root */
    call .Lregister
    jc .Lbad
    mov r13, rbx
    lea rsi, [rip+.Lpackage]
    call .Lkey_equal
    jne .Ltail
    mov [rsp+16], rbx
    jmp .Ltail

.Lassignment:
    call .Lkey
    jc .Lbad
    call .Lspace
    cmp al, '='
    jne .Lbad
    inc r12
    mov byte ptr [rsi], 0         /* consume delimiter before terminating bare key */
    mov rdx, r13
    call .Lregister
    jc .Lbad
    call .Lspace
    test r13, r13
    jz .Lvalue
    cmp r13, [rsp+16]
    jne .Lvalue
    lea rsi, [rip+.Lversion]
    call .Lkey_equal
    jne .Lvalue
    mov rdi, r12
    mov al, [rdi]
    call elan_toml_string
    jc .Lbad                      /* lean_version must have TOML string type */
    mov r14, r11
    mov r12, rdi
    jmp .Lafter_value
.Lvalue:
    mov al, [r12]
    cmp al, 34
    je .Lstring
    cmp al, 39
    je .Lstring
    cmp al, '{'
    je .Linline
    lea rsi, [rip+.Ltrue]
    cmp al, 't'
    je .Lboolean
    lea rsi, [rip+.Lfalse]
    cmp al, 'f'
    je .Lboolean
    /* Plain signed decimal integers. Cap magnitude even for unused fields. */
    mov r10, 0x7fffffffffffffff
    cmp al, '-'
    jne .Lplus
    inc r10
    jmp .Lsign
.Lplus:
    cmp al, '+'
    jne .Ldigits
.Lsign:
    inc r12
.Ldigits:
    movzx edx, byte ptr [r12]
    sub edx, '0'
    cmp edx, 9
    ja .Lbad
    inc r12
    mov eax, edx
    test edx, edx
    jz .Lafter_value
.Lnumber:
    movzx edx, byte ptr [r12]
    sub edx, '0'
    cmp edx, 9
    ja .Lafter_value
    mov rcx, 922337203685477580
    cmp rax, rcx
    ja .Lbad
    imul rax, rax, 10
    add rax, rdx
    cmp rax, r10
    ja .Lbad
    inc r12
    jmp .Lnumber
.Lstring:
    mov rdi, r12
    call elan_toml_string
    jc .Lbad
    mov r12, rdi
    jmp .Lafter_value
.Lboolean:
    lodsb
    test al, al
    jz .Lafter_value
    cmp al, [r12]
    jne .Lbad
    inc r12
    jmp .Lboolean
.Linline:
    cmp qword ptr [rsp+8], 0       /* this subset permits a single inline level */
    jne .Lbad
    mov [rsp], r13
    mov qword ptr [rsp+8], 1
    test r13, r13
    jnz .Lenter_inline
    lea rsi, [rip+.Lpackage]
    call .Lkey_equal
    jne .Lenter_inline
    mov [rsp+16], rbx
.Lenter_inline:
    mov r13, rbx
    inc r12
    call .Lspace
    cmp al, '}'
    je .Lclose_inline
    jmp .Lassignment
.Lafter_value:
    cmp qword ptr [rsp+8], 0
    je .Ltail
    call .Lspace
    cmp al, '}'
    je .Lclose_inline
    cmp al, ','
    jne .Lbad
    inc r12
    jmp .Lassignment              /* forbids trailing comma */
.Lclose_inline:
    inc r12
    mov qword ptr [rsp+8], 0
    mov r13, [rsp]
.Ltail:
    call .Lspace
    test al, al
    jz .Lsuccess
    cmp al, '#'
    je .Lcomment
    cmp al, 10
    je .Lnewline
    cmp al, 13
    jne .Lbad
.Lcrlf:
    inc r12
    cmp byte ptr [r12], 10
    jne .Lbad
.Lnewline:
    inc r12
    jmp .Lline
.Lcomment:
    inc r12
    mov al, [r12]
    test al, al
    jz .Lsuccess
    cmp al, 10
    je .Lnewline
    cmp al, 13
    je .Lcrlf
    cmp al, 9
    je .Lcomment
    cmp al, 0x20
    jb .Lbad
    cmp al, 0x7f
    jne .Lcomment
.Lbad:
    mov rax, -1
    jmp .Lreturn
.Lsuccess:
    mov rax, r14
.Lreturn:
    add rsp, FRAME_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size elan_leanpkg_version, .-elan_leanpkg_version

/* Read a key to rbx and leave its ending cursor in rsi. The caller consumes
 * the following delimiter before writing the NUL for unquoted names.
 */
.Lkey:
    sub rsp, 8
    call .Lspace
    cmp al, 34
    je .Lquoted_key
    cmp al, 39
    je .Lquoted_key
    mov rbx, r12
.Lbare:
    mov al, [r12]
    cmp al, '-'
    je .Lbare_byte
    cmp al, '_'
    je .Lbare_byte
    sub al, '0'
    cmp al, 9
    jbe .Lbare_byte
    mov al, [r12]
    or al, 32
    sub al, 'a'
    cmp al, 25
    ja .Lbare_end
.Lbare_byte:
    inc r12
    jmp .Lbare
.Lbare_end:
    mov rsi, r12
    cmp rsi, rbx
    je .Lkey_bad
    clc
    jmp .Lkey_return
.Lquoted_key:
    mov rdi, r12
    call elan_toml_string
    jc .Lkey_bad
    mov rbx, r11
    mov r12, rdi
    clc
    jmp .Lkey_return
.Lkey_bad:
    stc
.Lkey_return:
    lea rsp, [rsp+8]
    ret

/* Whitespace between TOML tokens excludes newline. */
.Lspace:
    mov al, [r12]
    cmp al, 9
    je .Lskip_byte
    cmp al, ' '
    jne .Lspaced
.Lskip_byte:
    inc r12
    jmp .Lspace
.Lspaced:
    ret

/* Compare the decoded key at rbx with a string at rsi; return ZF. */
.Lkey_equal:
    mov rdi, rbx
.Lequal_byte:
    lodsb
    cmp al, [rdi]
    jne .Lequal_done
    inc rdi
    test al, al
    jnz .Lequal_byte
.Lequal_done:
    ret

/* Each namespace has distinct keys. Compare owner identities before strings.
 * The local array also detects root assignment/table header collisions.
 */
.Lregister:
    cmp r15d, KEY_LIMIT
    jae .Lregister_bad
    mov r9, rbp
    mov ecx, r15d
.Lexisting:
    test ecx, ecx
    jz .Lnew
    cmp [r9], rdx
    jne .Lnext
    mov rsi, [r9+8]
    mov rdi, rbx
.Lduplicate:
    lodsb
    cmp al, [rdi]
    jne .Lnext
    test al, al
    jz .Lregister_bad
    inc rdi
    jmp .Lduplicate
.Lnext:
    add r9, 16
    dec ecx
    jmp .Lexisting
.Lnew:
    mov [r9], rdx
    mov [r9+8], rbx
    inc r15d
    clc
    ret
.Lregister_bad:
    stc
    ret

.section .rodata
.Lpackage: .asciz "package"
.Lversion: .asciz "lean_version"
.Ltrue:    .asciz "true"
.Lfalse:   .asciz "false"
.section .note.GNU-stack,"",@progbits
