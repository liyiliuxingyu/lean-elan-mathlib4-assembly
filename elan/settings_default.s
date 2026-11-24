/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Read the schema emitted by Elan 4.2.4 Settings::stringify (settings.rs).
 *
 * SysV: rdi is a writable NUL-terminated UTF-8 string with no embedded NUL.
 * Returns a pointer inside the buffer, 0 for no default, or -1 for bad or
 * unsupported settings. The caller owns the buffer, including on failure.
 *
 * Required: version = "2" or "12". Optional: default_toolchain (string),
 * telemetry (boolean), final [overrides] table. Top-level keys are bare.
 * Table entries map quoted or bare directory keys to resolved descriptors.
 * On success elan_override_count counts pairs of pointers into this buffer
 * at elan_override_entries. The single-shot launcher permits 2048 entries.
 * On failure the count is zero. A later call replaces the table.
 * Accept LF, CRLF, horizontal whitespace, comments, plain single-quoted
 * and double-quoted strings. Decode short escapes and non-NUL Unicode scalar
 * escapes in basic strings. Multiline strings and inline tables are outside
 * this subset. Reject unknown top-level keys, duplicate keys, and other tables.
 */
.intel_syntax noprefix
.section .text
.globl elan_settings_default
.type elan_settings_default, @function
elan_settings_default:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                  /* resolved descriptor (five qwords) */
    /* rdi = input cursor, r12d = keys seen, r13 = default string */
    xor r12d, r12d
    xor r13d, r13d
    mov qword ptr [rip+.Lcount], 0
.Lline:
    call .Lspace
    test al, al
    jz .Ldone
    cmp al, '#'
    je .Lcomment
    cmp al, 10
    je .Lnext_line
    cmp al, 13
    je .Lcrlf
    test r12b, 8
    jnz .Loverride_key
    cmp al, '['
    je .Ltable
    cmp al, 'v'
    je .Lversion
    cmp al, 't'
    je .Ltelemetry
    cmp al, 'd'
    jne .Lbad
    lea rsi, [rip+.Ldefault_name]
    mov r10d, 2
    jmp .Lfield
.Lversion:
    lea rsi, [rip+.Lversion_name]
    mov r10d, 1
    jmp .Lfield
.Ltelemetry:
    lea rsi, [rip+.Ltelemetry_name]
    mov r10d, 4
.Lfield:
    test r12d, r10d
    jnz .Lbad
    or r12d, r10d
    call .Lliteral
    jc .Lbad
    call .Lspace
    cmp al, '='
    jne .Lbad
    inc rdi
    call .Lspace
    cmp r10d, 4
    je .Lboolean
    call .Lquoted
    jc .Lbad
    cmp r10d, 1
    je .Lcheck_version
    mov r13, r11
    jmp .Ltail
.Lcheck_version:
    cmp byte ptr [r11], '1'
    jne .Lversion_two
    inc r11
.Lversion_two:
    cmp word ptr [r11], '2'       /* "2" followed by NUL */
    jne .Lbad
    jmp .Ltail
.Lboolean:
    lea rsi, [rip+.Ltrue]
    cmp al, 't'
    je .Lboolean_word
    lea rsi, [rip+.Lfalse]
.Lboolean_word:
    call .Lliteral
    jc .Lbad
    jmp .Ltail
.Ltable:
    inc rdi
    call .Lspace
    lea rsi, [rip+.Loverrides]
    call .Lliteral
    jc .Lbad
    call .Lspace
    cmp al, ']'
    jne .Lbad
    inc rdi
    or r12d, 8
    jmp .Ltail

.Loverride_key:
    cmp qword ptr [rip+.Lcount], 2048
    jae .Lbad
    cmp al, 34
    je .Lquoted_key
    cmp al, 39
    je .Lquoted_key
    mov rbx, rdi
.Lbare_key:
    mov al, [rdi]
    cmp al, '-'
    je .Lbare_byte
    cmp al, '_'
    je .Lbare_byte
    sub al, '0'
    cmp al, 9
    jbe .Lbare_byte
    mov al, [rdi]
    or al, 32
    sub al, 'a'
    cmp al, 25
    ja .Lbare_end
.Lbare_byte:
    inc rdi
    jmp .Lbare_key
.Lbare_end:
    cmp rbx, rdi
    je .Lbad
    mov r14, rdi                 /* terminate only after consuming '=' */
    jmp .Loverride_equals
.Lquoted_key:
    call .Lquoted
    jc .Lbad
    mov rbx, r11
    mov r14, rsi                 /* already points at terminating NUL */
.Loverride_equals:
    call .Lspace
    cmp al, '='
    jne .Lbad
    inc rdi
    mov byte ptr [r14], 0
    call .Lspace
    call .Lquoted
    jc .Lbad
    mov r14, rdi                 /* preserve cursor and decoded descriptor */
    mov r15, r11
    mov rdi, r11
    sub rsi, r11                 /* length of decoded descriptor */
    mov rdx, rsp
    call elan_parse_resolved
    test eax, eax
    jz .Lbad

    lea rdx, [rip+.Lentries]
    mov rcx, [rip+.Lcount]
.Lcheck_duplicate:
    test rcx, rcx
    jz .Lstore_override
    mov rsi, [rdx]
    mov rdi, rbx
.Lcompare_keys:
    lodsb
    cmp al, [rdi]
    jne .Lnext_entry
    test al, al
    jz .Lbad
    inc rdi
    jmp .Lcompare_keys
.Lnext_entry:
    add rdx, 16
    dec rcx
    jmp .Lcheck_duplicate
.Lstore_override:
    mov [rdx], rbx
    mov [rdx+8], r15
    inc qword ptr [rip+.Lcount]
    mov rdi, r14
.Ltail:
    call .Lspace
    test al, al
    jz .Ldone
    cmp al, '#'
    je .Lcomment
    cmp al, 10
    je .Lnext_line
    cmp al, 13
    jne .Lbad
.Lcrlf:
    inc rdi
    cmp byte ptr [rdi], 10
    jne .Lbad
.Lnext_line:
    inc rdi
    jmp .Lline
.Lcomment:
    inc rdi
    mov al, [rdi]
    test al, al
    jz .Ldone
    cmp al, 10
    je .Lnext_line
    cmp al, 13
    je .Lcrlf
    cmp al, 9
    je .Lcomment
    cmp al, 0x20
    jb .Lbad
    cmp al, 0x7f
    jne .Lcomment
.Lbad:
    mov qword ptr [rip+.Lcount], 0
    mov rax, -1
    jmp .Lreturn
.Ldone:
    test r12b, 1
    jz .Lbad
    mov rax, r13
.Lreturn:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size elan_settings_default, .-elan_settings_default

/* Decode one TOML string in place, with rdi at the quote and al = [rdi].
 * rdi advances past the closing quote.
 * r11 = start, rsi = terminating NUL of the decoded bytes. CF = failure.
 */
.globl elan_toml_string
.type elan_toml_string, @function
elan_toml_string:
.Lquoted:
    cmp al, 39
    je .Lstring
    cmp al, 34
    jne .Lfailure
.Lstring:
    mov dl, al                    /* quote delimiter */
    inc rdi
    mov r11, rdi                  /* beginning of decoded value */
    mov rsi, rdi                  /* write cursor <= read cursor */
.Lstring_byte:
    mov al, [rdi]
    inc rdi
    cmp al, dl
    je .Lend_string
    cmp al, 9
    je .Lwrite_byte
    cmp al, 0x20
    jb .Lfailure
    cmp al, 0x7f
    je .Lfailure
    cmp al, 92
    jne .Lwrite_byte
    cmp dl, 34
    jne .Lwrite_byte
    mov al, [rdi]
    inc rdi
    cmp al, 34
    je .Lwrite_byte
    cmp al, 92
    je .Lwrite_byte
    cmp al, 'u'
    je .Lshort_unicode
    cmp al, 'U'
    je .Llong_unicode
    lea rcx, [rip+.Lescapes]
.Lescape:
    cmp byte ptr [rcx], 0
    je .Lfailure
    cmp al, [rcx]
    je .Lemit_escape
    add rcx, 2
    jmp .Lescape
.Lemit_escape:
    mov al, [rcx+1]
.Lwrite_byte:
    mov [rsi], al
    inc rsi
    jmp .Lstring_byte
/* The four or eight hex digits encode one scalar. In-place conversion
 * is safe: the UTF-8 output is shorter than either input escape. */
.Lshort_unicode:
    mov r9d, 4
    jmp .Lunicode
.Llong_unicode:
    mov r9d, 8
.Lunicode:
    xor r8d, r8d
.Lhex_digit:
    movzx ecx, byte ptr [rdi]
    lea eax, [rcx-'0']
    cmp eax, 9
    jbe .Ladd_hex
    or ecx, 32
    lea eax, [rcx-'a']
    cmp eax, 5
    ja .Lfailure
    add eax, 10
.Ladd_hex:
    shl r8d, 4
    or r8d, eax
    inc rdi
    dec r9d
    jnz .Lhex_digit
    test r8d, r8d
    jz .Lfailure                  /* all returned strings are NUL-terminated */
    mov eax, r8d
    cmp eax, 0x7f
    jbe .Lwrite_byte
    cmp eax, 0x7ff
    ja .Lutf8_three
    shr eax, 6
    or al, 0xc0
    jmp .Llast_two
.Lutf8_three:
    cmp eax, 0xffff
    ja .Lutf8_four
    lea ecx, [rax-0xd800]
    cmp ecx, 0x7ff
    jbe .Lfailure                 /* surrogate range */
    shr eax, 12
    or al, 0xe0
    jmp .Llast_three
.Lutf8_four:
    cmp eax, 0x10ffff
    ja .Lfailure
    shr eax, 18
    or al, 0xf0
    mov [rsi], al
    inc rsi
    mov eax, r8d
    shr eax, 12
    and al, 0x3f
    or al, 0x80
.Llast_three:
    mov [rsi], al
    inc rsi
    mov eax, r8d
    shr eax, 6
    and al, 0x3f
    or al, 0x80
.Llast_two:
    mov [rsi], al
    inc rsi
    mov eax, r8d
    and al, 0x3f
    or al, 0x80
    jmp .Lwrite_byte
.Lend_string:
    mov byte ptr [rsi], 0
    clc
    ret
.size elan_toml_string, .-elan_toml_string

/* Move past horizontal whitespace, leave the next byte in al. */
.Lspace:
    mov al, [rdi]
    cmp al, ' '
    je .Lspace_next
    cmp al, 9
    jne .Lspace_done
.Lspace_next:
    inc rdi
    jmp .Lspace
.Lspace_done:
    ret

/* Consume the NUL-terminated literal at rsi. CF = mismatch. */
.Lliteral:
    mov al, [rsi]
    test al, al
    jz .Lliteral_done
    cmp [rdi], al
    jne .Lfailure
    inc rsi
    inc rdi
    jmp .Lliteral
.Lliteral_done:
    ret                           /* test cleared CF */
.Lfailure:
    stc
    ret

.section .rodata
.Lversion_name: .asciz "version"
.Ldefault_name: .asciz "default_toolchain"
.Ltelemetry_name: .asciz "telemetry"
.Loverrides: .asciz "overrides"
.Ltrue: .asciz "true"
.Lfalse: .asciz "false"
.Lescapes: .byte 'b', 8, 't', 9, 'n', 10, 'f', 12, 'r', 13, 0
.section .bss
.balign 8
.globl elan_override_count
.type elan_override_count, @object
elan_override_count:
.Lcount: .skip 8
.size elan_override_count, .-elan_override_count

.globl elan_override_entries
.type elan_override_entries, @object
elan_override_entries:
.Lentries: .skip 2048*16
.size elan_override_entries, .-elan_override_entries

.section .note.GNU-stack,"",@progbits
