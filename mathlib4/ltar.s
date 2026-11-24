# SPDX-License-Identifier: Apache-2.0
# Read members and metadata using the leangz 0.1.15 LTAR / LTR2 wire format.
.intel_syntax noprefix
.include "olean_layout.inc"
.equ MODE_COMMENTS, 1
.equ MODE_LIST, 2
.equ MODE_CAT, 3
.equ MODE_LOOKUP, 4
.equ MODE_TERM, 5
.equ OUT_CAP, 8192

.section .rodata
.Lflag_comments: .asciz "-k"
.Lflag_list:     .asciz "--list"
.Lflag_cat:      .asciz "--cat"
.Lflag_lookup:   .asciz "--lookup"
.Lflag_term:     .asciz "--term"
.Lusage:         .ascii "usage: mathlib-ltar {-k|--list} FILE.ltar\n"
                 .ascii "       mathlib-ltar --cat FILE.ltar MEMBER\n"
                 .ascii "       mathlib-ltar --lookup FILE.ltar NAME [NAME ...]\n"
                 .ascii "       mathlib-ltar --term FILE.ltar THEOREM\n"
.equ USAGE_LEN, . - .Lusage
.Lbad_input:     .ascii "mathlib-ltar: invalid archive or unreadable input\n"
.equ ERROR_LEN, . - .Lbad_input
.Lbad_output:    .ascii "mathlib-ltar: output error\n"
.equ OUTPUT_LEN, . - .Lbad_output
.align 4
.Lencodings:
    .long .Lzstd - .Lencodings, .Llgz - .Lencodings
    .long .Lplain - .Lencodings, .Ljson - .Lencodings, .Ltrace - .Lencodings
.Lzstd:  .asciz "zstd\t"
.Llgz:   .asciz "lgz\t"
.Lplain: .asciz "hash-plain\t"
.Ljson:  .asciz "hash-json\t"
.Ltrace: .asciz "header-hash\t"
.Lnl:    .byte 10
.Lhex:   .ascii "0123456789abcdef"

.bss
.balign 8
.Larchive:      .skip 8
.Larchive_size: .skip 8
.Lused:  .skip 8
.Lout:   .skip OUT_CAP

.text
.globl _start
.type _start,@function
_start:
    cmp qword ptr [rsp], 3
    jb .Lusage_error
    jne .Lpayload_arguments
    mov rdi, [rsp + 16]
    lea rsi, [rip + .Lflag_comments]
    call .Lequal
    mov ecx, MODE_COMMENTS
    test eax, eax
    jnz .Lopen
    mov rdi, [rsp + 16]
    lea rsi, [rip + .Lflag_list]
    call .Lequal
    test eax, eax
    jz .Lusage_error
    mov ecx, MODE_LIST
    jmp .Lopen
.Lpayload_arguments:
    lea rax, [rsp + 32]
    mov [rip + .Larguments], rax
    mov rax, [rsp]
    sub rax, 3
    mov [rip + .Larg_count], rax
    mov rdi, [rsp + 16]
    lea rsi, [rip + .Lflag_lookup]
    call .Lequal
    mov ecx, MODE_LOOKUP
    test eax, eax
    jnz .Lopen
    cmp qword ptr [rsp], 4
    jne .Lusage_error
    mov rdi, [rsp + 16]
    lea rsi, [rip + .Lflag_cat]
    call .Lequal
    mov ecx, MODE_CAT
    test eax, eax
    jnz .Lopen
    mov rdi, [rsp + 16]
    lea rsi, [rip + .Lflag_term]
    call .Lequal
    mov ecx, MODE_TERM
    test eax, eax
    jz .Lusage_error
.Lopen:
    mov r15d, ecx
    mov rdi, [rsp+24]
    lea rsi, [rip+.Larchive]
    lea rdx, [rip+.Larchive_size]
    call mathlib_ltar_map
    test eax, eax
    jnz .Linvalid

    mov rdi, [rip+.Larchive]
    mov rsi, [rip+.Larchive_size]
    cmp r15d, MODE_LOOKUP
    jae .Lfind_module
    cmp r15d, MODE_CAT
    je .Lfind_member

    # Validate the whole archive before emitting any list or comment output.
    xor edx, edx
    xor ecx, ecx
    call mathlib_ltar_walk
    test eax, eax
    jnz .Linvalid
    mov rdi, [rip+.Larchive]
    mov rsi, [rip+.Larchive_size]
    lea rdx, [rip+.Lprint_record]
    mov ecx, r15d
    call mathlib_ltar_walk
    test eax, eax
    jnz .Linvalid
    call .Lflush
    xor edi, edi
    jmp .Lexit

.Lfind_module:
    lea rdx, [rip+.Lselected_data]
    lea rcx, [rip+.Lselected_size]
    call mathlib_ltar_find_olean
    cmp eax, -2
    je .Lno_olean
    cmp eax, -3
    je .Lambiguous
    test eax, eax
    jnz .Linvalid
    mov ebx, 1                         # LGZ
    jmp .Lhandle_payload

.Lfind_member:
    lea rdx, [rip+.Lselect_exact]
    mov rcx, [rip+.Larguments]
    mov rcx, [rcx]
    call mathlib_ltar_walk
    test eax, eax
    jnz .Linvalid
    cmp qword ptr [rip+.Lmatch_count], 1
    ja .Lambiguous
    jb .Lno_match
    mov ebx, [rip+.Lselected_kind]
    jmp .Lhandle_payload

.Lequal:
    mov al, [rdi]
    cmp al, [rsi]
    jne .Ldifferent
    inc rdi
    inc rsi
    test al, al
    jnz .Lequal
    mov eax, 1
    ret
.Ldifferent:
    xor eax, eax
    ret

# mathlib_ltar_walk callback(mode, kind, name, name_length, data, length).
.Lprint_record:
    cmp esi, 5
    je .Lprint_comment
    cmp edi, MODE_LIST
    jne .Lprint_done
    push rbx
    push rbp
    sub rsp, 24
    mov rbx, rdx                       # path needed by .Lpath
    mov rbp, rcx
    sub r8, [rip+.Larchive]
    mov [rsp], r8                      # stored payload offset
    mov [rsp+8], r9
    lea rdi, [rip+.Lencodings]
    movsxd rsi, dword ptr [rdi+rsi*4]
    add rsi, rdi
    call .Lput_cstr
    mov rax, [rsp]
    call .Ldecimal_tab
    mov rax, [rsp+8]
    call .Ldecimal_tab
    call .Lpath
    add rsp, 24
    pop rbp
    pop rbx
    jmp .Lnewline
.Lprint_comment:
    cmp edi, MODE_COMMENTS
    jne .Lprint_done
    mov rsi, rdx
    mov rdx, rcx
    sub rsp, 8
    call .Lput
    add rsp, 8
    jmp .Lnewline
.Lprint_done:
    ret

# Keep UTF-8 path text readable, escape field delimiters, ASCII controls
# and the escape introducer. Stream arbitrary-length names into .Lout.
.Lpath:
    sub rsp, 8
    lea r8, [rbx + rbp]             # end of validated path
    mov r9, rbx                     # first byte of pending literal run
    mov r10, rbx                    # byte being inspected
.Lpath_byte:
    cmp r10, r8
    je .Lpath_end
    movzx eax, byte ptr [r10]
    cmp al, 32
    jb .Lpath_escape
    cmp al, 127
    je .Lpath_escape
    cmp al, 92
    jne .Lpath_advance
.Lpath_escape:
    mov rsi, r9
    mov rdx, r10
    sub rdx, r9
    call .Lput
    movzx eax, byte ptr [r10]
    lea rdi, [rip + .Lhex]
    mov ecx, eax
    shr eax, 4
    and ecx, 15
    mov word ptr [rsp], 0x785c
    mov al, [rdi + rax]
    mov cl, [rdi + rcx]
    mov [rsp + 2], al
    mov [rsp + 3], cl
    mov rsi, rsp
    mov edx, 4
    call .Lput
    lea r9, [r10 + 1]
.Lpath_advance:
    inc r10
    jmp .Lpath_byte
.Lpath_end:
    mov rsi, r9
    mov rdx, r10
    sub rdx, r9
    add rsp, 8
    jmp .Lput

.Ldecimal_tab:
    sub rsp, 32
    lea rsi, [rsp + 31]
    mov byte ptr [rsi], 9
    jmp .Ldigits
.Ldecimal_text:
    sub rsp, 32
    lea rsi, [rsp + 32]
.Ldigits:
    mov ecx, 10
.Ldigit:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .Ldigit
    lea rdx, [rsp + 32]
    sub rdx, rsi
    call .Lput
    add rsp, 32
    ret
.Lnewline:
    lea rsi, [rip + .Lnl]
    mov edx, 1
.Lput:
    test rdx, rdx
    jz .Lput_done
    mov rax, [rip + .Lused]
    mov ecx, OUT_CAP
    sub rcx, rax
    jnz .Lput_copy
    push rsi
    push rdx
    call .Lflush
    pop rdx
    pop rsi
    jmp .Lput
.Lput_copy:
    cmp rcx, rdx
    cmova rcx, rdx
    lea rdi, [rip + .Lout]
    add rdi, rax
    add [rip + .Lused], rcx
    sub rdx, rcx
    rep movsb
    jmp .Lput
.Lput_done:
    ret
.Lflush:
    mov rdx, [rip + .Lused]
    lea rsi, [rip + .Lout]
.Lwrite:
    test rdx, rdx
    jz .Lflushed
    mov edi, 1
    mov eax, 1
    syscall
    cmp rax, -4                     # EINTR
    je .Lwrite
    test rax, rax
    jle .Lwrite_error
    add rsi, rax
    sub rdx, rax
    jmp .Lwrite
.Lflushed:
    mov qword ptr [rip + .Lused], 0
    ret
.Lusage_error:
    lea rsi, [rip + .Lusage]
    mov edx, USAGE_LEN
    jmp .Lerror
.Linvalid:
    lea rsi, [rip + .Lbad_input]
    mov edx, ERROR_LEN
    jmp .Lerror
.Lwrite_error:
    lea rsi, [rip + .Lbad_output]
    mov edx, OUTPUT_LEN
.Lerror:
    mov r8d, 2
.Lreport:
    mov edi, 2
    mov eax, 1
    syscall
    cmp rax, -4
    je .Lreport
    test rax, rax
    jle .Lreported
    add rsi, rax
    sub rdx, rax
    jnz .Lreport
.Lreported:
    mov edi, r8d
.Lexit:
    mov eax, 60
    syscall
.include "ltar_payload.inc"
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
