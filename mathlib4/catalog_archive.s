# SPDX-License-Identifier: Apache-2.0
# Decode an archive-backed Lean module with caller-owned output.
.intel_syntax noprefix
.include "olean_layout.inc"
.text
.globl mathlib_ltar_decode_olean
.type mathlib_ltar_decode_olean,@function
# (compressed, size, &olean, &olean_size) -> 0 or -1. Caller owns the mmap.
mathlib_ltar_decode_olean:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov r12, rdx
    mov r13, rcx
    mov qword ptr [r12], 0
    mov qword ptr [r13], 0
    lea rdx, [rip+mathlib_zstd_dict]
    lea rcx, [rip+mathlib_zstd_dict_end]
    sub rcx, rdx
    mov r8, rsp                      # temporary LGZ stream mapping
    lea r9, [rsp+8]
    call mathlib_ltar_zstd_stream
    test eax, eax
    jnz .Ldecode_error
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    mov rdx, r12
    mov rcx, r13
    call lgz_decode
    mov ebx, eax
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    test rsi, rsi                    # even an empty stream owns one page
    jnz .Lfree_stream
    inc esi
.Lfree_stream:
    mov eax, 11
    syscall
    mov eax, ebx
    jmp .Ldecode_return
.Ldecode_error:
    mov eax, -1
.Ldecode_return:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
.size mathlib_ltar_decode_olean,.-mathlib_ltar_decode_olean

.globl catalog_open_module
.type catalog_open_module,@function
# (archive_path, view[64], &archive_hash) -> 0 or -1.
# On success munmap(view[VIEW_MAPPING], view[VIEW_SIZE]) after using the view.
# Failure clears the outputs. The hash is unkeyed XXH64 of the entire archive.
catalog_open_module:
    push rbx
    push r12
    push r13
    sub rsp, 48                      # three (address, length) pairs
    mov r12, rsi                     # caller's view
    mov r13, rdx                     # caller's hash
    lea rsi, [rsp]                   # archive
    lea rdx, [rsp+8]
    call mathlib_ltar_map
    test eax, eax
    jnz .Lclear
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    lea rdx, [rsp+16]                # selected compressed span
    lea rcx, [rsp+24]
    call mathlib_ltar_find_olean
    test eax, eax
    jnz .Lfailed_archive
    mov rdi, [rsp+16]
    mov rsi, [rsp+24]
    lea rdx, [rsp+32]                # reconstructed .olean
    lea rcx, [rsp+40]
    call mathlib_ltar_decode_olean
    test eax, eax
    jnz .Lfailed_archive
    mov rdi, [rsp+32]
    mov rsi, [rsp+40]
    mov rdx, r12
    call mathlib_olean_parse
    cmp eax, 1
    jne .Lfailed_image
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    call asm_zstd_xxh64
    mov [r13], rax
    xor ebx, ebx                     # view now owns the image
    jmp .Lunmap_archive
.Lfailed_image:
    mov rdi, [rsp+32]
    mov rsi, [rsp+40]
    mov eax, 11
    syscall
.Lfailed_archive:
    mov ebx, -1
.Lunmap_archive:
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    mov eax, 11
    syscall
    test ebx, ebx
    jz .Lopen_return
.Lclear:
    xor eax, eax
    mov [r13], rax
    mov rdi, r12
    mov ecx, VIEW_BYTES/8
    rep stosq
    mov ebx, -1
.Lopen_return:
    mov eax, ebx
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret
.size catalog_open_module,.-catalog_open_module
.section .note.GNU-stack,"",@progbits
