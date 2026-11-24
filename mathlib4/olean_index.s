# SPDX-License-Identifier: Apache-2.0
# Shortlist candidate declarations by their final name component.
.intel_syntax noprefix
.include "olean_layout.inc"
.text
.globl mathlib_olean_index_new
.type mathlib_olean_index_new,@function
# (view, outstanding queries) -> temporary index or NULL for linear lookup.
# An unusable leaf or allocation failure falls back to the original reader,
# which preserves demand-driven diagnostics for malformed metadata.
mathlib_olean_index_new:
    cmp rsi, 16
    jb .Lnone
    mov rax, [rdi + VIEW_COUNT]
    cmp rax, 64
    jb .Lnone
    cmp rax, 0x1000000
    ja .Lnone
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rax
    lea rax, [r13 - 1]
    bsr rcx, rax
    inc ecx
    mov r14d, 1
    shl r14, cl                     # At least one bucket per declaration.
    lea rsi, [r14 + r13]
    lea rsi, [rsi * 4 + INDEX_HEADS]
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, 9                      # mmap
    syscall
    cmp rax, -4095
    jae .Lunavailable
    mov r15, rax
    mov [r15 + INDEX_SIZE], rsi
    lea rax, [r15 + r14*4 + INDEX_HEADS]
    mov [r15 + INDEX_LINKS], rax
    dec r14
    mov [r15 + INDEX_MASK], r14
    # Reverse insertion keeps candidates in original declaration order.
.Lnext:
    test r13d, r13d
    jz .Lcomplete
    dec r13
    mov rax, [r12 + VIEW_NAMES]
    mov rsi, [rax + r13*8]
    cmp rsi, 1
    je .Lnext
    mov rdi, r12
    mov edx, 32
    call mathlib_olean_object
    test rax, rax
    jz .Ldiscard
    movzx ebx, word ptr [rax + 6]
    mov rdi, [rax + 16]
    cmp ebx, 0x0202                 # Name.num
    je .Lnumber
    cmp ebx, 0x0102                 # Name.str
    jne .Ldiscard
    mov rsi, rdi
    mov rdi, r12
    mov edx, 32
    call mathlib_olean_object
    test rax, rax
    jz .Ldiscard
    cmp byte ptr [rax + 7], 249
    jne .Ldiscard
    mov rsi, [rax + 8]
    test rsi, rsi
    jz .Ldiscard
    lea rdi, [rax + 32]
    mov rdx, [r12 + VIEW_MAPPING]
    add rdx, [r12 + VIEW_SIZE]
    sub rdx, rdi
    cmp rsi, rdx
    ja .Ldiscard
    dec rsi
    cmp byte ptr [rdi + rsi], 0
    jne .Ldiscard
    jmp .Linsert
.Lnumber:
    mov rsi, -1
.Linsert:
    call mathlib_olean_leaf_hash
    and eax, r14d
    lea rdi, [r15 + rax*4 + INDEX_HEADS]
    mov eax, [rdi]
    mov rdx, [r15 + INDEX_LINKS]
    mov [rdx + r13*4], eax
    lea eax, [r13d + 1]
    mov [rdi], eax
    jmp .Lnext
.Ldiscard:
    mov rdi, r15
    call mathlib_olean_index_free
.Lunavailable:
    xor r15d, r15d
.Lcomplete:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.Lnone:
    xor eax, eax
    ret
.size mathlib_olean_index_new, .-mathlib_olean_index_new

.globl mathlib_olean_index_free
.type mathlib_olean_index_free,@function
mathlib_olean_index_free:
    test rdi, rdi
    jz .Lfree_done
    mov rsi, [rdi + INDEX_SIZE]
    mov eax, 11                     # munmap
    syscall
.Lfree_done:
    ret
.size mathlib_olean_index_free, .-mathlib_olean_index_free

.globl mathlib_olean_leaf_hash
.hidden mathlib_olean_leaf_hash
.type mathlib_olean_leaf_hash,@function
# (bytes, length) or (boxed natural number, -1). Exact comparison follows.
mathlib_olean_leaf_hash:
    cmp rsi, -1
    je .Lhash_num
    mov eax, 0x811c9dc5
    lea rcx, [rdi + rsi]
.Lhash_byte:
    cmp rdi, rcx
    je .Lhash_end
    movzx edx, byte ptr [rdi]
    xor eax, edx
    imul eax, eax, 0x01000193
    inc rdi
    jmp .Lhash_byte
.Lhash_num:
    mov rax, rdi
    shr rax, 32
    xor eax, edi
    imul eax, eax, 0x9e3779b1
.Lhash_end:
    ret
.size mathlib_olean_leaf_hash, .-mathlib_olean_leaf_hash
.section .note.GNU-stack,"",@progbits
