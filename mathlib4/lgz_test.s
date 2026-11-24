# SPDX-License-Identifier: Apache-2.0
# Exercise fail-closed ABI behavior for framing errors and every proper prefix
# of a valid normal-mode stream. The caller's output slots start nonzero.
.intel_syntax noprefix
.text
.globl _start
.type _start,@function
_start:
    sub rsp, 16
    lea r12, [rip+lgz_normal_start]
    lea r13, [rip+lgz_normal_end]
    sub r13, r12
    xor ebx, ebx
.Lprefix:
    mov rdi, r12
    mov rsi, rbx
    call .Lexpect_invalid
    inc rbx
    cmp rbx, r13
    jb .Lprefix

    lea r12, [rip+.Lcases]
    lea r13, [rip+.Lcases_end]
.Lcase:
    movsxd rdi, dword ptr [r12]
    add rdi, r12
    mov esi, [r12+4]
    call .Lexpect_invalid
    add r12, 8
    cmp r12, r13
    jb .Lcase
    xor edi, edi
    jmp .Lexit
.Lexpect_invalid:
    sub rsp, 24
    mov qword ptr [rsp], -1
    mov qword ptr [rsp+8], -1
    mov rdx, rsp
    lea rcx, [rsp+8]
    call lgz_decode
    cmp eax, -1
    jne .Lfailed
    cmp qword ptr [rsp], 0
    jne .Lfailed
    cmp qword ptr [rsp+8], 0
    jne .Lfailed
    add rsp, 24
    ret
.Lfailed:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall
.size _start,.-_start

.section .rodata
.macro begin label
.L\label:
    .ascii "LGZ!"
    .long 0
    .quad 32
.endm
begin forward
.byte 0xf0
.Lforward_end:
begin trailing
.byte 0xd0,0xd1
.Ltrailing_end:
begin bad_expr
.byte 0x80,0x11
.Lbad_expr_end:
begin bad_arity
.byte 0,0xf8,-1
.Lbad_arity_end:
begin bad_save
.byte 0xff,0xfc,0
.Lbad_save_end:
begin bad_ctor_size
.byte 0x10,0,255
.short 8190
.Lbad_ctor_size_end:
begin bad_array_length
.byte 0,0xfb
.quad 0x4000000000000000
.Lbad_array_length_end:
begin bad_mpz
.byte 0x40,0xd0
.Lbad_mpz_end:
begin bad_name
.byte 0x80,0,0xd0,0xd0
.Lbad_name_end:
begin bad_local_ref
.byte 0x02,0xfd
.short 42
.Lbad_local_ref_end:
.Lbad_flags:
.ascii "LGZ2"
.long 18
.quad 96
.zero 40
.byte 3,4,19,0,255,0xd0
.Lbad_flags_end:
.Lcases:
.macro cas label
    .long .L\label-.,.L\label\()_end-.L\label
.endm
cas forward
cas trailing
cas bad_expr
cas bad_arity
cas bad_save
cas bad_ctor_size
cas bad_array_length
cas bad_mpz
cas bad_name
cas bad_local_ref
cas bad_flags
.Lcases_end:
.section .note.GNU-stack,"",@progbits
