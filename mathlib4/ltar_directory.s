# SPDX-License-Identifier: Apache-2.0
# Shared read-only archive mapping, LTAR/LTR2 directory validation and selection.
.intel_syntax noprefix
.text
.globl mathlib_ltar_map
.type mathlib_ltar_map,@function
# (path, &mapping, &length) -> 0 or -1. The caller owns a successful mmap.
mathlib_ltar_map:
    push rbx
    push r12
    push r13
    sub rsp, 144                     # x86-64 Linux struct stat
    mov r12, rsi
    mov r13, rdx
    mov qword ptr [r12], 0
    mov qword ptr [r13], 0
    mov rsi, rdi
    mov edi, -100                    # AT_FDCWD
    mov edx, 0x80800                 # O_RDONLY | O_NONBLOCK | O_CLOEXEC
    xor r10d, r10d
.Lopen:
    mov eax, 257                     # openat
    syscall
    cmp rax, -4
    je .Lopen
    test rax, rax
    js .Lmap_error
    mov ebx, eax
    mov edi, ebx
    mov rsi, rsp
.Lstat:
    mov eax, 5                       # fstat
    syscall
    cmp rax, -4
    je .Lstat
    test rax, rax
    js .Lclose
    mov eax, [rsp+24]
    and eax, 0xf000
    cmp eax, 0x8000
    jne .Lclose
    mov rsi, [rsp+48]
    cmp rsi, 14                      # magic, hash, nonempty path, NUL
    jl .Lclose
    xor edi, edi
    mov edx, 1                       # PROT_READ
    mov r10d, 2                      # MAP_PRIVATE
    mov r8d, ebx
    xor r9d, r9d
    mov eax, 9
    syscall
    cmp rax, -4095
    jae .Lclose
    mov [r12], rax
    mov [r13], rsi
.Lclose:
    mov edi, ebx
    mov eax, 3
    syscall
    cmp qword ptr [r13], 0
    je .Lmap_error
    xor eax, eax
    jmp .Lmap_return
.Lmap_error:
    mov eax, -1
.Lmap_return:
    add rsp, 144
    pop r13
    pop r12
    pop rbx
    ret
.size mathlib_ltar_map,.-mathlib_ltar_map

.globl mathlib_ltar_walk
.type mathlib_ltar_walk,@function
# (base, length, optional callback, context) -> 0 valid, -1 malformed.
# Calls callback(context, kind, name, name_length, payload, payload_length)
# once per record. Kinds 0..3 are on-wire tags, 4 is the LTAR header hash,
# 5 is a comment (text in name; null payload). All spans borrow the mapping.
# Callbacks may see valid records before a subsequent invalid record.
mathlib_ltar_walk:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov [rsp], rdi
    mov r14, rdx                     # callback
    mov r15, rcx                     # context
    cmp rsi, 14
    jb .Lbad
    mov r13, rdi
    add r13, rsi                     # end (exclusive)
    jc .Lbad
    lea r12, [rdi+12]                # cursor
    cmp dword ptr [rdi], 0x3252544c  # LTR2
    je .Lheader
    cmp dword ptr [rdi], 0x5241544c  # LTAR
    jne .Lbad
.Lheader:
    call .Ltext
    test eax, eax
    jz .Lbad
    test rbp, rbp
    jz .Lbad
    mov r8, [rsp]
    cmp dword ptr [r8], 0x3252544c
    je .Lmember
    add r8, 4                        # LTAR's first trace is the header hash
    mov r9d, 8
    mov esi, 4
    jmp .Ldispatch
.Lnext:
    cmp r12, r13
    je .Lvalid
    call .Ltext
    test eax, eax
    jz .Lbad
    test rbp, rbp
    jnz .Lmember
    call .Ltext                      # empty path introduces a comment
    test eax, eax
    jz .Lbad
    mov esi, 5
    xor r8d, r8d
    xor r9d, r9d
    jmp .Ldispatch
.Lmember:
    mov rax, r13
    sub rax, r12
    cmp rax, 9                       # tag and eight-byte value or length
    jb .Lbad
    movzx esi, byte ptr [r12]
    inc r12
    cmp esi, 3
    ja .Lbad
    mov r9d, 8
    cmp esi, 2
    jae .Lspan
    mov r9, [r12]
    add r12, 8
.Lspan:
    mov rax, r13
    sub rax, r12
    cmp r9, rax
    ja .Lbad
    mov r8, r12
    add r12, r9
.Ldispatch:
    test r14, r14
    jz .Lnext
    mov rdi, r15
    mov rdx, rbx
    mov rcx, rbp
    call r14
    jmp .Lnext
.Lvalid:
    xor eax, eax
    jmp .Lwalk_return
.Lbad:
    mov eax, -1
.Lwalk_return:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

# Consume one bounded NUL-terminated UTF-8 string. Return its address and
# byte length in rbx/rbp for the current record; eax reports validity.
.Ltext:
    mov rcx, r13
    sub rcx, r12
    jz .Lno_string
    mov rbx, r12
    mov rdi, r12
    xor eax, eax
    repne scasb
    jne .Lno_string
    mov r12, rdi
    lea rbp, [rdi-1]
    sub rbp, rbx
    sub rsp, 24
    mov qword ptr [rsp], 0
    mov qword ptr [rsp+8], 0
    mov rdi, rbx
    mov rsi, rbp
    mov rdx, rsp                     # byte position
    lea rcx, [rsp+8]                 # scalar count
    call _ZN4lean13validate_utf8EPKhmRmS2_
    add rsp, 24
    ret
.Lno_string:
    xor eax, eax
    ret
.size mathlib_ltar_walk,.-mathlib_ltar_walk

.globl mathlib_ltar_find_olean
.type mathlib_ltar_find_olean,@function
# (base, length, &compressed, &size). Success 0, invalid archive -1,
# missing LGZ .olean -2, multiple LGZ .olean members -3.
mathlib_ltar_find_olean:
    push r12
    push r13
    sub rsp, 24                      # match count, payload, length
    mov r12, rdx
    mov r13, rcx
    mov qword ptr [r12], 0
    mov qword ptr [r13], 0
    mov qword ptr [rsp], 0
    lea rdx, [rip+.Lselect]
    mov rcx, rsp
    call mathlib_ltar_walk
    test eax, eax
    jnz .Lfind_return
    cmp qword ptr [rsp], 1
    jb .Lmissing
    ja .Lmultiple
    mov rax, [rsp+8]
    mov [r12], rax
    mov rax, [rsp+16]
    mov [r13], rax
    xor eax, eax
    jmp .Lfind_return
.Lmultiple:
    mov eax, -3
    jmp .Lfind_return
.Lmissing:
    mov eax, -2
.Lfind_return:
    add rsp, 24
    pop r13
    pop r12
    ret
.Lselect:
    cmp esi, 1                       # LGZ
    jne .Lselect_done
    cmp rcx, 6
    jb .Lselect_done
    cmp word ptr [rdx+rcx-6], 0x6f2e
    jne .Lselect_done
    cmp dword ptr [rdx+rcx-4], 0x6e61656c
    jne .Lselect_done
    inc qword ptr [rdi]
    mov [rdi+8], r8
    mov [rdi+16], r9
.Lselect_done:
    ret
.size mathlib_ltar_find_olean,.-mathlib_ltar_find_olean
.section .note.GNU-stack,"",@progbits
