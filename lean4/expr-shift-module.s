# SPDX-License-Identifier: Apache-2.0
# Test one v4.19.0 .olean. Enumerate every unique Expr reachable from theorem
# types and proofs. Compare stock and assembly in the same process, on the
# same borrowed compacted object, without interposing on the stock DSO.
.intel_syntax noprefix
.section .rodata
.Lsummary: .asciz "%lu %lu %lu %lu\n"
.Lmismatch: .asciz "shift mismatch at node %lu, tag %u, operation %u (0=lift), cutoff %u, delta %u\n"
.Lusage: .asciz "usage: expr-shift-module FILE.olean\n"
.Lbad_tag: .asciz "invalid expression tag in compacted theorem\n"
.Lalloc_error: .asciz "cannot allocate expression worklist\n"
.Lparams: .byte 0,1, 1,1, 2,1, 2,2, 3,2, 4,1
.equ NPARAM, (. - .Lparams)/2
# Each pair gives the byte offset of the first Expr child and the child count.
.Lchildren: .byte 0,0, 0,0, 0,0, 0,0, 0,0, 8,2, 16,2, 16,2, 16,3, 0,0, 16,1, 24,1
.section .data.rel.ro
.balign 8
.Lops: .quad lean_expr_lift_loose_bvars, asm_expr_lift_loose_bvars
       .quad lean_expr_lower_loose_bvars, asm_expr_lower_loose_bvars
.bss
.balign 8
.Lseen: .skip 8
.Lqueue: .skip 8
.Lcapacity: .skip 8
.Lcount: .skip 8
.Ltheorems: .skip 8
.Lcomparisons: .skip 8
.Lchanged: .skip 8
.Lreader: .skip 8
.Lregion: .skip 8
.Lfilename: .skip 8

.text
.globl main
.type main,@function
main:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp edi, 2
    jne .Lusage_error
    mov rax, [rsi + 8]
    mov [rip + .Lfilename], rax
    call lean_initialize_runtime_module@PLT
    mov edi, 1
    mov esi, 1
    call initialize_Lean_Environment@PLT
    cmp byte ptr [rax + 7], 0
    jne .Lio_error
    mov rdi, rax
    call .Ldrop
    call lean_io_mark_end_initialization@PLT

    mov rdi, [rip + .Lfilename]
    call lean_mk_string@PLT
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call lean_read_module_data@PLT
    mov [rip + .Lreader], rax
    mov rdi, rbx                         # path is borrowed by the reader
    call .Ldrop
    mov rax, [rip + .Lreader]
    cmp byte ptr [rax + 7], 0
    jne .Lio_error
    mov rax, [rax + 8]                   # IO result contains the pair
    mov rdx, [rax + 16]                  # boxed CompactedRegion (USize)
    mov rdx, [rdx + 8]
    mov [rip + .Lregion], rdx
    mov rax, [rax + 8]                   # ModuleData
    mov r12, [rax + 24]                  # Array ConstantInfo
    xor r13d, r13d
.Ldeclaration:
    cmp r13, [r12 + 8]
    jae .Lwalk
    mov rax, [r12 + r13*8 + 24]
    inc r13
    cmp byte ptr [rax + 7], 2            # ConstantInfo.thmInfo
    jne .Ldeclaration
    inc qword ptr [rip + .Ltheorems]
    mov r14, [rax + 8]                   # TheoremVal
    mov rax, [r14 + 8]                   # ConstantVal
    mov rdi, [rax + 24]                  # ConstantVal.type
    call .Lenqueue
    mov rdi, [r14 + 16]                  # TheoremVal.value
    call .Lenqueue
    jmp .Ldeclaration

.Lwalk:
    xor r13d, r13d
.Lnode:
    cmp r13, [rip + .Lcount]
    jae .Ldone
    mov rax, [rip + .Lqueue]
    mov r12, [rax + r13*8]
    movzx eax, byte ptr [r12 + 7]
    cmp eax, 11
    ja .Ltag_error
    lea rcx, [rip + .Lchildren]
    movzx r14d, byte ptr [rcx + rax*2]
    movzx r15d, byte ptr [rcx + rax*2 + 1]
    add r14, r12
.Lchild:
    test r15d, r15d
    jz .Lqueries
    mov rdi, [r14]
    call .Lenqueue
    add r14, 8
    dec r15d
    jmp .Lchild
.Lqueries:
    xor r14d, r14d
.Lop:
    xor r15d, r15d
.Lparams_loop:
    call .Lcompare
    test eax, eax
    jz .Ldiffer
    inc qword ptr [rip + .Lcomparisons]
    inc r15d
    cmp r15d, NPARAM
    jb .Lparams_loop
    inc r14d
    cmp r14d, 2
    jb .Lop
    inc r13
    jmp .Lnode

.Ldone:
    lea rdi, [rip + .Lsummary]
    mov rsi, [rip + .Ltheorems]
    mov rdx, [rip + .Lcount]
    mov rcx, [rip + .Lcomparisons]
    mov r8, [rip + .Lchanged]
    xor eax, eax
    call printf@PLT
    mov ebx, eax
    shr ebx, 31
    jmp .Lfinish_module
.Ldiffer:
    lea rax, [rip + .Lparams]
    movzx r8d, byte ptr [rax + r15*2]
    movzx r9d, byte ptr [rax + r15*2 + 1]
    mov rsi, r13
    movzx edx, byte ptr [r12 + 7]
    mov ecx, r14d
    lea rdi, [rip + .Lmismatch]
    xor eax, eax
    call printf@PLT
    mov ebx, 3
    jmp .Lfinish_module
.Ltag_error:
    mov edi, 2
    lea rsi, [rip + .Lbad_tag]
    xor eax, eax
    call dprintf@PLT
    mov ebx, 2
.Lfinish_module:
    mov rdi, [rip + .Lseen]
    test rdi, rdi
    jz .Lfree_queue
    lea rsi, [rip + .Lskip_key]          # all keys are borrowed from the module
    call tdestroy@PLT
.Lfree_queue:
    mov rdi, [rip + .Lqueue]
    call free@PLT
    mov rdi, [rip + .Lreader]
    call .Ldrop
    mov rdi, [rip + .Lregion]            # all references to its objects released
    mov esi, 1
    call lean_compacted_region_free@PLT
    mov rdi, rax
    call .Ldrop
    xor edi, edi
    call fflush@PLT
    test eax, eax
    jz .Lstatus
    mov ebx, 1
.Lstatus:
    mov eax, ebx
    jmp .Lexit
.Lusage_error:
    mov edi, 2
    lea rsi, [rip + .Lusage]
    xor eax, eax
    call dprintf@PLT
    mov eax, 2
    jmp .Lexit
.Lio_error:
    mov rbx, rax
    mov rdi, rbx
    call lean_io_result_show_error@PLT
    mov rdi, rbx
    call .Ldrop
    mov eax, 2
.Lexit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size main, .-main

# libc search tree gives O(log N) lookup without retaining compacted nodes.
.Lpointer_cmp:
    xor eax, eax
    xor edx, edx
    cmp rdi, rsi
    seta al
    setb dl
    sub eax, edx
.Lskip_key:
    ret
.Lenqueue:
    push rbx
    mov rbx, rdi
    lea rsi, [rip + .Lseen]
    lea rdx, [rip + .Lpointer_cmp]
    call tfind@PLT
    test rax, rax
    jnz .Lqueued
    mov rdi, rbx
    lea rsi, [rip + .Lseen]
    lea rdx, [rip + .Lpointer_cmp]
    call tsearch@PLT
    test rax, rax
    jz .Loom
    mov rax, [rip + .Lcount]
    cmp rax, [rip + .Lcapacity]
    jb .Lappend
    mov esi, 64
    test rax, rax
    jz .Lresize
    lea rsi, [rax + rax]
    cmp rsi, rax
    jbe .Loom
.Lresize:
    mov [rip + .Lcapacity], rsi
    mov rdi, [rip + .Lqueue]
    mov edx, 8
    call reallocarray@PLT
    test rax, rax
    jz .Loom
    mov [rip + .Lqueue], rax
    mov rax, [rip + .Lcount]
.Lappend:
    mov rdx, [rip + .Lqueue]
    mov [rdx + rax*8], rbx
    inc qword ptr [rip + .Lcount]
.Lqueued:
    pop rbx
    ret
.Loom:
    mov edi, 2
    lea rsi, [rip + .Lalloc_error]
    xor eax, eax
    call dprintf@PLT
    mov edi, 2
    call exit@PLT

# r12=node, r14=operation, r15=parameter pair. Evaluate on the same borrowed
# input and include only that operation in its heartbeat interval.
.Lcompare:
    push rbx
    sub rsp, 48
    mov eax, r14d
    shl eax, 4
    lea rbx, [rip + .Lops]
    add rbx, rax
    lea rax, [rip + .Lparams]
    movzx esi, byte ptr [rax + r15*2]
    movzx edx, byte ptr [rax + r15*2 + 1]
    lea esi, [rsi*2 + 1]
    lea edx, [rdx*2 + 1]
    mov [rsp], rsi
    mov [rsp + 8], rdx
    call _ZN4lean18get_num_heartbeatsEv@PLT
    mov [rsp + 16], rax
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call [rbx]
    mov [rsp + 24], rax
    call _ZN4lean18get_num_heartbeatsEv@PLT
    mov rcx, rax
    sub rcx, [rsp + 16]
    mov [rsp + 32], rcx
    mov [rsp + 16], rax
    mov rdi, r12
    mov rsi, [rsp]
    mov rdx, [rsp + 8]
    call [rbx + 8]
    mov [rsp + 40], rax
    call _ZN4lean18get_num_heartbeatsEv@PLT
    sub rax, [rsp + 16]
    xor ebx, ebx
    cmp rax, [rsp + 32]
    jne .Lrelease
    mov rdi, [rsp + 24]
    mov rsi, [rsp + 40]
    cmp rdi, r12
    setne cl
    cmp rsi, r12
    setne dl
    cmp cl, dl
    jne .Lrelease
    movzx ecx, cl
    add [rip + .Lchanged], rcx
    call lean_expr_equal@PLT
    movzx ebx, al
.Lrelease:
    mov rdi, [rsp + 24]
    call .Ldrop
    mov rdi, [rsp + 40]
    call .Ldrop
    mov eax, ebx
    add rsp, 48
    pop rbx
    ret

.Ldrop:
    mov eax, [rdi]
    cmp eax, 1
    jg .Llocal
    test eax, eax
    jne lean_dec_ref_cold@PLT
    ret
.Llocal:
    dec dword ptr [rdi]
    ret

.section .note.GNU-stack,"",@progbits
