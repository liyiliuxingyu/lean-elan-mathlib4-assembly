# SPDX-License-Identifier: Apache-2.0
# Optional test oracle. Read one publisher-produced module through the official
# Lean DSO and print its ConstantInfo kinds and names in declaration-array order.
.intel_syntax noprefix
.section .rodata
.Lrow: .asciz "%s\t%s\n"
.Laxiom: .asciz "axiom"
.Ldef: .asciz "definition"
.Lthm: .asciz "theorem"
.Lopaque: .asciz "opaque"
.Lquot: .asciz "quotient"
.Lind: .asciz "inductive"
.Lctor: .asciz "constructor"
.Lrec: .asciz "recursor"
.section .data.rel.ro
.balign 8
.Lkinds: .quad .Laxiom, .Ldef, .Lthm, .Lopaque, .Lquot, .Lind, .Lctor, .Lrec
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
    jne .Lerror
    mov rbx, [rsi + 8]
    call lean_initialize_runtime_module@PLT
    mov edi, 1
    mov esi, 1
    call initialize_Lean_Environment@PLT
    cmp byte ptr [rax + 7], 0
    jne .Lio_error
    mov rdi, rax
    call .Ldrop
    call lean_io_mark_end_initialization@PLT
    mov rdi, rbx
    call lean_mk_string@PLT
    mov rbx, rax
    mov rdi, rax
    mov esi, 1
    call lean_read_module_data@PLT
    mov r15, rax
    mov rdi, rbx
    call .Ldrop
    mov rax, r15
    cmp byte ptr [rax + 7], 0
    jne .Lio_error
    mov rax, [rax + 8]                  # (ModuleData × CompactedRegion)
    mov rax, [rax + 8]
    mov r12, [rax + 16]                 # constNames
    mov r13, [rax + 24]                 # constants
    mov rcx, [r12 + 8]
    cmp rcx, [r13 + 8]
    jne .Lerror
    xor ebx, ebx
.Lnext:
    cmp rbx, [r12 + 8]
    jae .Ldone
    mov rdi, [r12 + 24 + rbx*8]        # compacted Name is persistent
    call l_Lean_Name_instToString@PLT
    mov r14, rax
    mov rcx, [r13 + 24 + rbx*8]
    movzx ecx, byte ptr [rcx + 7]
    cmp ecx, 7
    ja .Lerror
    lea rsi, [rip + .Lkinds]
    mov rsi, [rsi + rcx*8]
    lea rdx, [r14 + 32]
    lea rdi, [rip + .Lrow]
    xor eax, eax
    call printf@PLT
    test eax, eax
    js .Lerror
    mov rdi, r14
    call .Ldrop
    inc rbx
    jmp .Lnext
.Ldone:
    # The driver runs once per module. Its compacted region lives until exit.
    mov rdi, r15
    call .Ldrop
    xor edi, edi
    call fflush@PLT
    test eax, eax
    setne al
    movzx eax, al
    jmp .Lexit
.Lio_error:
    mov rdi, rax
    call lean_io_result_show_error@PLT
.Lerror:
    mov eax, 2
.Lexit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size main, .-main

.Ldrop:
    mov ecx, [rdi]
    cmp ecx, 1
    jg .Lshared
    test ecx, ecx
    jne lean_dec_ref_cold@PLT
    ret
.Lshared:
    dec dword ptr [rdi]
    ret
.section .note.GNU-stack,"",@progbits
