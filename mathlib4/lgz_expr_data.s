# SPDX-License-Identifier: Apache-2.0
# Encode the cached scalar words elided by the exprish opcodes in leangz
# v0.1.15, src/lgz.rs. Name hashes use 64 bits. Level and Expr hashes use
# the low 32 bits, with flags, depth and loose bound variables packed above.
.intel_syntax noprefix

.text
.globl lgz_expr_data
.type lgz_expr_data,@function
# int lgz_expr_data(opcode, fields, output, validbytes, base, gmp, result)
# fields contains the serialized pointer words of the node being built.
# output and base correspond to the same byte, respectively in memory and in
# the compacted file's address space. Return 0 on success or -1 on bad input.
lgz_expr_data:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp+32], r9d                # GMP layout selector
    cmp ebx, 15
    ja .Lmore_ops
    lea rax, [rip+.Lops]
    movsxd rcx, dword ptr [rax+rbx*4]
    add rax, rcx
    jmp rax
.Lmore_ops:
    cmp ebx, 0x18
    jb .Lfail
    cmp ebx, 0x1f
    jbe .Lbinder
    cmp ebx, 0x21
    je .Lapp
    cmp ebx, 0x40
    je .Lconst
    jmp .Lfail

.macro FETCH field, kind
    mov rax, [r12+8*\field]
    call .Lget_\kind
    jc .Lfail
.endm

.Lname_str:
    FETCH 0, name
    mov [rsp], rax
    FETCH 1, string
    mov rsi, rax
    mov rdi, [rsp]
    call .Lmix
    jmp .Ldone
.Lname_num:
    FETCH 0, name
    mov rdi, rax
    mov rsi, [r12+8]
    shr rsi, 1
    jc .Lname_num_mix
    mov esi, 17                     # upstream's hash for a heap numeral here
.Lname_num_mix:
    call .Lmix
    jmp .Ldone

.Llevel_succ:
    FETCH 0, level
    mov esi, eax
    shr rax, 32
    lea ecx, [rax+256]              # low byte holds flags, upper 24 hold depth
    mov edi, 2243
    call .Lmix
    jmp .Lpack_upper
.Llevel_binary:
    FETCH 0, level
    mov [rsp], rax
    FETCH 1, level
    mov rdx, [rsp]
    mov edi, edx
    mov esi, eax
    shr rdx, 32
    shr rax, 32
    mov ecx, edx
    or cl, al                       # union of the two flag bytes
    shr edx, 8
    shr eax, 8
    cmp eax, edx
    cmovb eax, edx
    inc eax
    shl eax, 8
    mov al, cl
    mov ecx, eax
    call .Lmix
    mov rsi, rax
    mov edi, 2251
    cmp ebx, 3
    je .Llevel_binary_mix
    mov edi, 2267
.Llevel_binary_mix:
    call .Lmix
    jmp .Lpack_upper
.Llevel_named:
    FETCH 0, name
    mov rsi, rax
    mov edi, 2239
    mov ecx, 2
    cmp ebx, 5
    je .Llevel_named_mix
    mov edi, 2237
    mov ecx, 1
.Llevel_named_mix:
    call .Lmix
    jmp .Lpack_upper

.Lbvar:
    FETCH 0, num
    mov rsi, rax
    lea ecx, [rax+1]
    shl ecx, 12                     # loose bound variable range
    mov edi, 7
    call .Lmix
    jmp .Lpack_upper
.Lvar:
    FETCH 0, name
    mov rsi, rax
    xor edi, edi
    call .Lmix
    mov rsi, rax
    mov edi, 13
    mov ecx, 0x100
    cmp ebx, 8
    je .Lvar_mix
    mov edi, 17
    mov ecx, 0x200
.Lvar_mix:
    call .Lmix
    jmp .Lpack_upper
.Lsort:
    FETCH 0, level
    mov esi, eax
    shr rax, 32
    movzx ecx, al
    shl cl, 2                       # convert level flags into expression flags
    shl ecx, 8
    mov edi, 11
    call .Lmix
    jmp .Lpack_upper
.Lliteral:
    mov rax, [r12]
    call .Lobject
    jc .Lfail
    cmp rdx, 16
    jb .Lfail
    cmp byte ptr [rax+6], 1
    jb .Lfail
    movzx ecx, byte ptr [rax+7]
    mov rax, [rax+8]
    test ecx, ecx
    jz .Llit_num
    cmp ecx, 1
    jne .Lfail
    call .Lget_string
    jmp .Llit_hash
.Llit_num:
    call .Lget_num
.Llit_hash:
    jc .Lfail
    mov rsi, rax
    mov edi, 3
    call .Lmix
    mov eax, eax
    jmp .Ldone

.Lconst:
    FETCH 0, name
    mov [rsp], rax
    mov qword ptr [rsp+8], 7        # list hash seed
    mov qword ptr [rsp+16], 0       # accumulated level flags
    mov rax, [r12+8]
.Llevels_loop:
    test al, 1
    jnz .Llevels_end
    mov [rsp+24], rax
    call .Lobject
    jc .Lfail
    cmp byte ptr [rax+7], 1
    jne .Llevels_end                # same prefix folding as leangz
    cmp byte ptr [rax+6], 2
    jb .Lfail
    cmp rdx, 24
    jb .Lfail
    mov rcx, [rax+16]
    test cl, 1
    jnz .Llevels_tail_ok
    cmp rcx, [rsp+24]               # compacted children precede their parent
    jae .Lfail
.Llevels_tail_ok:
    mov [rsp+24], rcx
    mov rax, [rax+8]
    call .Lget_level
    jc .Llevels_end
    mov esi, eax
    shr rax, 32
    or [rsp+16], al
    mov rdi, [rsp+8]
    call .Lmix
    mov [rsp+8], rax
    mov rax, [rsp+24]
    jmp .Llevels_loop
.Llevels_end:
    mov rdi, [rsp]
    mov rsi, [rsp+8]
    call .Lmix
    mov rsi, rax
    mov edi, 5
    call .Lmix
    mov ecx, [rsp+16]
    shl cl, 2
    shl ecx, 8
    jmp .Lpack_upper

# Compound expressions combine one, two or three previously cached words.
# rsp+0/+8/+16 hold their original data, rsp+24 the nested operand hash.
.Lmdata:
    FETCH 1, scalar
    mov [rsp], rax
    mov eax, eax
    mov [rsp+24], rax
    jmp .Lsingle_flags
.Lproj:
    FETCH 2, scalar
    mov [rsp], rax
    FETCH 1, num
    mov rdi, rax
    mov esi, [rsp]
    call .Lmix
    mov [rsp+24], rax
    FETCH 0, name
    mov rdi, rax
    mov rsi, [rsp+24]
    call .Lmix
    mov [rsp+24], rax
.Lsingle_flags:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov rdi, [rsp]
    xor esi, esi
    call .Lmerge_flags
    jmp .Ldepth_hash

.Lapp:
    FETCH 0, scalar
    mov [rsp], rax
    FETCH 1, scalar
    mov [rsp+8], rax
    mov rsi, rax
    mov rdi, [rsp]
    call .Lmix                       # apps mix all 64 bits of each operand
    mov [rsp+24], rax
    jmp .Lpair_flags
.Lbinder:
    FETCH 1, scalar
    mov [rsp], rax
    FETCH 2, scalar
    mov [rsp+8], rax
    mov esi, eax
    jmp .Lbinder_hash
.Llet:
    FETCH 1, scalar
    mov [rsp], rax
    FETCH 2, scalar
    mov [rsp+8], rax
    FETCH 3, scalar
    mov [rsp+16], rax
    mov esi, eax
    mov edi, [rsp+8]
    call .Lmix
    mov rsi, rax
.Lbinder_hash:
    mov edi, [rsp]
    call .Lmix
    mov [rsp+24], rax
.Lpair_flags:
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov rdi, [rsp]
    xor esi, esi
    call .Lmerge_flags
    mov rdi, [rsp+8]
    cmp ebx, 0x21
    je .Lapp_flags
    cmp ebx, 0x18
    jae .Lbody_flags
    xor esi, esi
    call .Lmerge_flags
    mov rdi, [rsp+16]
.Lbody_flags:
    mov esi, 1                      # binder consumes a loose variable in body
    call .Lmerge_flags
.Ldepth_hash:
    lea edi, [rcx+1]                # salt may reach 256 at saturated depth
    mov rsi, [rsp+24]
    call .Lmix
    jmp .Lexpr_pack
.Lapp_flags:
    xor esi, esi
    call .Lmerge_flags
    mov rax, [rsp+24]
.Lexpr_pack:
    cmp ecx, 255
    je .Ldepth_ready
    inc ecx
.Ldepth_ready:
    shl edx, 12
    shl r8d, 8
    or ecx, edx
    or ecx, r8d
.Lpack_upper:
    mov eax, eax
    shl rcx, 32
    or rax, rcx
.Ldone:
    mov rcx, [rbp+16]
    mov [rcx], rax
    xor eax, eax
    jmp .Lreturn
.Lfail:
    mov eax, -1
.Lreturn:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size lgz_expr_data,.-lgz_expr_data

# Merge one packed Expr (rdi) into max depth ecx, max loose variable range
# edx and union of flags r8d. esi = 1 subtracts one binder, saturating at 0.
.Lmerge_flags:
    shr rdi, 32
    movzx eax, dil
    cmp eax, ecx
    cmova ecx, eax
    shr edi, 8
    mov eax, edi
    and eax, 15
    or r8d, eax
    shr edi, 4
    sub edi, esi
    jb .Lmerge_done
    cmp edi, edx
    cmova edx, edi
.Lmerge_done:
    ret

# Mix a hash rdi with a key rsi. Lean's mixHash uses XOR with the multiplier
# after the shift, unlike the MurmurHash2 block step in the string hash.
# Preserve rcx, rdx, r8 and r9 across this local helper.
.Lmix:
    movabs r10, 0xc6a4a7935bd1e995
    imul rsi, r10
    mov rax, rsi
    shr rax, 47
    xor rax, rsi
    xor rax, r10
    xor rax, rdi
    imul rax, r10
    ret

# Resolve a boxed pointer, returning host address rax and available bytes rdx.
.Lobject:
    sub rax, r15
    jc .Lbad_object
    test al, 7
    jnz .Lbad_object
    mov rdx, r14
    sub rdx, rax
    jc .Lbad_object
    cmp rdx, 8
    jb .Lbad_object
    add rax, r13
    ret                             # no carry for an in-range mapped address
.Lbad_object:
    stc
    ret
.Lget_name:
    cmp rax, 1
    jne .Lget_scalar
    mov eax, 1723                   # Name.anonymous
    ret
.Lget_level:
    cmp rax, 1
    jne .Lget_scalar
    mov eax, 2221                   # Level.zero
    ret
.Lget_scalar:
    call .Lobject
    jc .Lbad_object
    movzx ecx, byte ptr [rax+6]
    lea rcx, [rcx*8+16]             # includes first scalar word
    movzx esi, word ptr [rax+4]
    cmp rsi, rcx
    jb .Lbad_object
    cmp rdx, rcx
    jb .Lbad_object
    mov rax, [rax+rcx-8]
    ret
.Lget_num:
    test al, 1
    jz .Lheap_num
    shr rax, 1
    clc
    ret
.Lheap_num:
    call .Lobject
    jc .Lbad_object
    cmp byte ptr [rax+7], 250
    jne .Lbad_object
    cmp dword ptr [rbp-48], 0        # caller's rsp+32
    je .Lportable_num
    cmp rdx, 32
    jb .Lbad_object
    cmp dword ptr [rax+8], 0
    je .Lbad_object
    mov ecx, [rax+12]
    mov rax, [rax+24]
    test ecx, ecx
    js .Lnegative_num
    ret
.Lportable_num:
    cmp rdx, 40
    jb .Lbad_object
    cmp qword ptr [rax+16], 0
    je .Lbad_object
    mov rcx, [rax+8]
    mov rax, [rax+32]
    test rcx, rcx
    jz .Lnum_ok
.Lnegative_num:
    neg rax
.Lnum_ok:
    clc
    ret
.Lget_string:
    call .Lobject
    jc .Lbad_object
    cmp byte ptr [rax+7], 249
    jne .Lbad_object
    sub rdx, 32
    jc .Lbad_object
    mov rdi, [rax+8]
    test rdi, rdi
    jz .Lbad_object
    cmp rdx, rdi
    jb .Lbad_object
    lea rsi, [rax+32]
    dec rdi                         # exclude the NUL from Lean's String hash
    cmp byte ptr [rsi+rdi], 0
    jne .Lbad_object
    mov edx, 11
    sub rsp, 8
    call _ZN4lean8hash_strEmPKhm
    add rsp, 8
    clc
    ret

.section .rodata
.balign 4
.Lops:
    .long .Lname_str-.Lops, .Lname_num-.Lops, .Llevel_succ-.Lops
    .long .Llevel_binary-.Lops, .Llevel_binary-.Lops
    .long .Llevel_named-.Lops, .Llevel_named-.Lops
    .long .Lbvar-.Lops, .Lvar-.Lops, .Lvar-.Lops, .Lsort-.Lops
    .long .Lliteral-.Lops, .Lmdata-.Lops, .Lproj-.Lops, .Llet-.Lops, .Llet-.Lops
.section .note.GNU-stack,"",@progbits
