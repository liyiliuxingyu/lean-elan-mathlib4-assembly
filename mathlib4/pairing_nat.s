# SPDX-License-Identifier: Apache-2.0
# Nat.pair and Nat.unpair, Mathlib/Data/Nat/Pairing.lean (v4.19.0).
# Big natural: limb count followed by little-endian qwords in radix 10^8.
# Count zero is canonical zero. The caller sizes the workspace from the inputs.
.intel_syntax noprefix
.equ RADIX, 100000000
.equ ROOT_RADIX, 10000
.text

# rdi = dest; rsi = src; rdx = multiplier; rcx = addend (initial carry).
# Multipliers in this module are <= 2*RADIX. dest may alias src.
.type scale_add,@function
scale_add:
    mov r8, [rsi]
    mov r9, rdx
    mov r10d, RADIX
    xor r11d, r11d
.Lscale:
    cmp r11, r8
    je .Lscale_tail
    mov rax, [rsi+r11*8+8]
    imul rax, r9
    add rax, rcx
    xor edx, edx
    div r10
    mov [rdi+r11*8+8], rdx
    mov rcx, rax
    inc r11
    jmp .Lscale
.Lscale_tail:
    test rcx, rcx
    jz .Lscale_done
    mov rax, rcx
    xor edx, edx
    div r10
    mov [rdi+r11*8+8], rdx
    mov rcx, rax
    inc r11
    jmp .Lscale_tail
.Lscale_done:
    mov [rdi], r11
    ret

# Return -1, 0 or 1 for the ordering of rdi and rsi.
.type compare,@function
compare:
    mov rcx, [rdi]
    cmp rcx, [rsi]
    jne .Lordered
.Lcmp:
    test rcx, rcx
    jz .Lequal
    mov rax, [rdi+rcx*8]
    cmp rax, [rsi+rcx*8]
    jne .Lordered
    dec rcx
    jmp .Lcmp
.Lordered:
    sbb eax, eax
    or eax, 1
    ret
.Lequal:
    xor eax, eax
    ret

# Normalize trailing high zero limbs in rdi.
.type trim,@function
trim:
    mov rcx, [rdi]
.Ltrim:
    test rcx, rcx
    jz .Ltrim_done
    cmp qword ptr [rdi+rcx*8], 0
    jne .Ltrim_done
    dec rcx
    jmp .Ltrim
.Ltrim_done:
    mov [rdi], rcx
    ret

# Add rsi to rdi in place.
.type add_nat,@function
add_nat:
    mov r8, [rdi]
    mov r9, [rsi]
    mov r10, r9
    cmp r8, r9
    cmova r10, r8
    xor ecx, ecx
    xor edx, edx
.Ladd:
    cmp rcx, r10
    je .Ladd_tail
    xor eax, eax
    cmp rcx, r8
    jae .Ladd_rhs
    mov rax, [rdi+rcx*8+8]
.Ladd_rhs:
    cmp rcx, r9
    jae .Ladd_carry
    add rax, [rsi+rcx*8+8]
.Ladd_carry:
    add rax, rdx
    xor edx, edx
    cmp rax, RADIX
    jb .Ladd_store
    sub rax, RADIX
    inc edx
.Ladd_store:
    mov [rdi+rcx*8+8], rax
    inc rcx
    jmp .Ladd
.Ladd_tail:
    test rdx, rdx
    jz .Ladd_done
    mov [rdi+rcx*8+8], rdx
    inc rcx
.Ladd_done:
    mov [rdi], rcx
    ret

# Subtract rsi from rdi in place, given rsi <= rdi.
.type sub_nat,@function
sub_nat:
    xor ecx, ecx
    xor edx, edx
.Lsub:
    cmp rcx, [rdi]
    je trim
    mov rax, [rdi+rcx*8+8]
    sub rax, rdx
    cmp rcx, [rsi]
    jae .Lborrow
    sub rax, [rsi+rcx*8+8]
.Lborrow:
    xor edx, edx
    test rax, rax
    jns .Lsub_store
    add rax, RADIX
    inc edx
.Lsub_store:
    mov [rdi+rcx*8+8], rax
    inc rcx
    jmp .Lsub

# Square rsi into disjoint storage rdi.
.type square,@function
square:
    push rbx
    push rbp
    push r12
    mov rbx, [rsi]
    lea rax, [rbx+rbx]
    mov [rdi], rax
    mov rcx, rax
    mov r12, rdi
    add rdi, 8
    xor eax, eax
    rep stosq
    mov rdi, r12
    mov r8d, RADIX
    xor r9d, r9d
.Lsquare_row:
    cmp r9, rbx
    je .Lsquare_done
    mov rbp, [rsi+r9*8+8]
    lea r12, [rdi+r9*8+8]
    xor r10d, r10d
    xor r11d, r11d
.Lproduct:
    mov rax, [rsi+r10*8+8]
    imul rax, rbp
    add rax, r11
    add rax, [r12+r10*8]
    xor edx, edx
    div r8
    mov [r12+r10*8], rdx
    mov r11, rax
    inc r10
    cmp r10, rbx
    jne .Lproduct
    mov [r12+r10*8], r11
    inc r9
    jmp .Lsquare_row
.Lsquare_done:
    pop r12
    pop rbp
    pop rbx
    jmp trim

# rdi = result (disjoint from inputs); rsi = a; rdx = b.
.globl mathlib_nat_pair
.type mathlib_nat_pair,@function
mathlib_nat_pair:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov rdi, rsi
    mov rsi, rdx
    call compare
    test eax, eax
    mov rdi, r12
    js .Lpair_right
    mov rsi, r13
    call square
    mov rdi, r12
    mov rsi, r13
    call add_nat
    mov rsi, r14
    jmp .Lpair_sum
.Lpair_right:
    mov rsi, r14
    call square
    mov rsi, r13
.Lpair_sum:
    mov rdi, r12
    pop r14
    pop r13
    pop r12
    jmp add_nat
.size mathlib_nat_pair,.-mathlib_nat_pair

# rdi = n, rsi = root, rdx = remainder, rcx = trial. Last three are work
# buffers. Returns pointers (rax,rdx) to the two coordinates in those buffers.
.globl mathlib_nat_unpair
.type mathlib_nat_unpair,@function
mathlib_nat_unpair:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov qword ptr [r13], 0
    mov qword ptr [r14], 0
    mov rbx, [r12]
.Lroot_group:
    test rbx, rbx
    jz .Lsplit
    # Pull down one base-10^8 group. Find x in [0,10000) maximal with
    # (2*10000*root + x)*x <= remainder. Appending x produces the new root.
    mov rcx, [r12+rbx*8]
    mov rdi, r14
    mov rsi, r14
    mov edx, RADIX
    call scale_add
    xor ebp, ebp                  # inclusive lower bound
    mov qword ptr [rsp], ROOT_RADIX  # exclusive upper bound
.Lroot_digit:
    mov rax, [rsp]
    sub rax, rbp
    cmp rax, 1
    je .Lroot_take
    shr rax, 1
    add rax, rbp
    mov [rsp+8], rax
    call .Ltrial
    mov rdi, r15
    mov rsi, r14
    call compare
    test eax, eax
    mov rax, [rsp+8]
    jg .Ltoo_big
    mov rbp, rax
    jmp .Lroot_digit
.Ltoo_big:
    mov [rsp], rax
    jmp .Lroot_digit
.Lroot_take:
    test rbp, rbp
    jz .Lappend
    mov rax, rbp
    call .Ltrial
    mov rdi, r14
    mov rsi, r15
    call sub_nat
.Lappend:
    mov rdi, r13
    mov rsi, r13
    mov edx, ROOT_RADIX
    mov rcx, rbp
    call scale_add
    dec rbx
    jmp .Lroot_group
.Lsplit:
    mov rdi, r14
    mov rsi, r13
    call compare
    test eax, eax
    js .Lremainder_first
    mov rdi, r14
    mov rsi, r13
    call sub_nat
    mov rax, r13
    mov rdx, r14
    jmp .Lroot_done
.Lremainder_first:
    mov rax, r14
    mov rdx, r13
.Lroot_done:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.Ltrial:
    mov rdi, r15
    mov rsi, r13
    imul rdx, rax, 2*ROOT_RADIX
    mov rcx, rax
    imul rcx, rax
    jmp scale_add
.size mathlib_nat_unpair,.-mathlib_nat_unpair
.section .note.GNU-stack,"",@progbits
