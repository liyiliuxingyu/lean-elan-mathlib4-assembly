# SPDX-License-Identifier: Apache-2.0
# Read archive metadata using the leangz 0.1.15 LTAR / LTR2 wire format.
.intel_syntax noprefix
.equ MODE_CHECK, 0
.equ MODE_COMMENTS, 1
.equ MODE_LIST, 2
.equ OUT_CAP, 8192

.section .rodata
.Lflag_comments: .asciz "-k"
.Lflag_list:     .asciz "--list"
.Lusage:         .ascii "usage: mathlib-ltar {-k|--list} FILE.ltar\n"
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
.Lmode:  .skip 8
.Lkind:  .skip 8
.Lstart: .skip 8
.Lsize:  .skip 8
.Lused:  .skip 8
.Lout:   .skip OUT_CAP

.text
.globl _start
.type _start,@function
_start:
    cmp qword ptr [rsp], 3
    jne .Lusage_error
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
.Lopen:
    mov [rip + .Lmode], rcx
    mov edi, -100                   # AT_FDCWD
    mov rsi, [rsp + 24]
    mov edx, 0x80800                # O_RDONLY | O_NONBLOCK | O_CLOEXEC
    xor r10d, r10d
.Lopen_retry:
    mov eax, 257                    # openat
    syscall
    cmp rax, -4
    je .Lopen_retry
    test rax, rax
    js .Linvalid
    mov ebx, eax
    sub rsp, 144                    # x86-64 Linux struct stat
    mov edi, ebx
    mov rsi, rsp
.Lstat_retry:
    mov eax, 5                      # fstat
    syscall
    cmp rax, -4
    je .Lstat_retry
    test rax, rax
    js .Linvalid
    mov eax, [rsp + 24]
    and eax, 0xf000
    cmp eax, 0x8000                 # regular file
    jne .Linvalid
    mov r13, [rsp + 48]
    add rsp, 144
    cmp r13, 14                     # magic, hash, nonempty path, NUL
    jb .Linvalid
    test r13, r13
    js .Linvalid
    xor edi, edi
    mov rsi, r13
    mov edx, 1                      # PROT_READ
    mov r10d, 2                     # MAP_PRIVATE
    mov r8d, ebx
    xor r9d, r9d
    mov eax, 9                      # mmap
    syscall
    cmp rax, -4095
    jae .Linvalid
    mov r12, rax                    # mapping start
    add r13, rax                    # mapping end
    mov edi, ebx
    mov eax, 3                      # close
    syscall

    # Check the full record framing and UTF-8 before reporting any result.
    # Neither pass accesses the compressed payload bytes.
    mov r15d, MODE_CHECK
    call .Lwalk
    mov r15, [rip + .Lmode]
    call .Lwalk
    call .Lflush
    xor edi, edi
    jmp .Lexit

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

# r12 = base, r13 = end, r14 = cursor. Each record retains its UTF-8
# name (rbx, rbp) while the cursor advances over its content.
.Lwalk:
    lea r14, [r12 + 12]
    cmp dword ptr [r12], 0x3252544c # LTR2
    je .Ltrace_v2
    cmp dword ptr [r12], 0x5241544c # LTAR
    jne .Linvalid
    call .Lread_text
    test rbp, rbp
    jz .Linvalid
    mov qword ptr [rip + .Lkind], 4
    mov qword ptr [rip + .Lstart], 4
    mov qword ptr [rip + .Lsize], 8
    jmp .Lmaybe_member
.Ltrace_v2:
    call .Lread_text
    test rbp, rbp
    jz .Linvalid
    jmp .Lmember
.Lnext_record:
    cmp r14, r13
    je .Lwalk_done
    call .Lread_text
    test rbp, rbp
    jnz .Lmember
    call .Lread_text                # empty path introduces a comment
    cmp r15d, MODE_COMMENTS
    jne .Lnext_record
    mov rsi, rbx
    mov rdx, rbp
    call .Lput
    call .Lnewline
    jmp .Lnext_record
.Lmember:
    mov rcx, r13
    sub rcx, r14
    cmp rcx, 9                      # tag + eight-byte size or hash
    jb .Linvalid
    movzx eax, byte ptr [r14]
    inc r14
    cmp eax, 3
    ja .Linvalid
    mov [rip + .Lkind], rax
    mov edx, 8
    cmp eax, 2
    jae .Lpayload
    mov rdx, [r14]                  # compressed length
    add r14, 8
.Lpayload:
    mov rax, r13
    sub rax, r14
    cmp rdx, rax
    ja .Linvalid
    mov rax, r14
    sub rax, r12
    mov [rip + .Lstart], rax
    mov [rip + .Lsize], rdx
    add r14, rdx
.Lmaybe_member:
    cmp r15d, MODE_LIST
    jne .Lnext_record
    mov rax, [rip + .Lkind]
    lea rsi, [rip + .Lencodings]
    movsxd rax, dword ptr [rsi + rax*4]
    add rsi, rax
    xor edx, edx
.Lencoding_end:
    inc rdx
    cmp byte ptr [rsi + rdx], 0
    jne .Lencoding_end
    call .Lput
    mov rax, [rip + .Lstart]
    call .Ldecimal_tab
    mov rax, [rip + .Lsize]
    call .Ldecimal_tab
    call .Lpath
    call .Lnewline
    jmp .Lnext_record
.Lwalk_done:
    ret

.Lread_text:
    mov rcx, r13
    sub rcx, r14
    jz .Linvalid
    mov rbx, r14
    mov rdi, r14
    xor eax, eax
    repne scasb
    jne .Linvalid
    mov r14, rdi
    lea rbp, [rdi - 1]
    sub rbp, rbx
    test r15d, r15d
    jnz .Ltext_ok
    push 0                          # byte position
    push 0                          # scalar count
    mov rdi, rbx
    mov rsi, rbp
    lea rdx, [rsp + 8]
    mov rcx, rsp
    call _ZN4lean13validate_utf8EPKhmRmS2_
    add rsp, 16
    test eax, eax
    jz .Linvalid
.Ltext_ok:
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
    mov edi, 2
    mov eax, 1
    syscall
    mov edi, 2
.Lexit:
    mov eax, 60
    syscall
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
