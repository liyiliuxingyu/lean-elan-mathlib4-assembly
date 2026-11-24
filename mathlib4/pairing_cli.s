# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.section .rodata
.Lpair:   .asciz "pair"
.Lunpair: .asciz "unpair"
.Lhelp:   .ascii "usage: mathlib-pairing pair A B | mathlib-pairing unpair N\n"
.equ HELP_LEN, .-.Lhelp
.Lbad:    .ascii "mathlib-pairing: expected a nonempty unsigned decimal integer\n"
.equ BAD_LEN, .-.Lbad
.Lmem:    .ascii "mathlib-pairing: cannot allocate workspace\n"
.equ MEM_LEN, .-.Lmem
.Lio:     .ascii "mathlib-pairing: output error\n"
.equ IO_LEN, .-.Lio
.text
.globl _start
.type _start,@function
_start:
    mov r12, rsp
    mov rax, [r12]
    cmp rax, 4
    je .Lpair_args
    cmp rax, 3
    jne .Lusage
    lea rsi, [rip+.Lunpair]
    jmp .Lmode
.Lpair_args:
    lea rsi, [rip+.Lpair]
.Lmode:
    mov rdi, [r12+16]
.Lmatch:
    lodsb
    cmp al, [rdi]
    jne .Lusage
    inc rdi
    test al, al
    jnz .Lmatch
    mov rdi, [r12+24]
    call .Ldigits
    mov r13, rax
    xor r14d, r14d
    cmp qword ptr [r12], 4
    jne .Lallocate
    mov rdi, [r12+32]
    call .Ldigits
    mov r14, rax
.Lallocate:
    # A slot holds twice the maximum operand length, rounded up, plus
    # carry and header space. Four slots hold naturals, one formats output.
    mov rbx, r13
    cmp rbx, r14
    cmovb rbx, r14
    shr rbx, 3
    lea rbx, [rbx+rbx+5]
    shl rbx, 3
    lea rsi, [rbx+rbx*4]
    xor edi, edi
    mov edx, 3                   # PROT_READ|PROT_WRITE
    mov r10d, 0x22               # MAP_PRIVATE|MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    cmp rax, -4095
    jae .Lno_mem
    mov r15, rax
    mov rdi, r15
    mov rsi, [r12+24]
    mov rcx, r13
    call .Lparse
    cmp qword ptr [r12], 4
    jne .Lunpair_run
    lea rdi, [r15+rbx]
    mov rsi, [r12+32]
    mov rcx, r14
    call .Lparse
    lea rdi, [r15+rbx*2]
    mov rsi, r15
    lea rdx, [r15+rbx]
    call mathlib_nat_pair
    lea rdi, [r15+rbx*2]
    jmp .Llast
.Lunpair_run:
    mov rdi, r15
    lea rsi, [r15+rbx]
    lea rdx, [r15+rbx*2]
    lea rcx, [rdx+rbx]
    call mathlib_nat_unpair
    mov r14, rdx
    mov rdi, rax
    lea rsi, [r15+rbx*4]
    mov edx, ' '
    call .Lprint
    mov rdi, r14
.Llast:
    lea rsi, [r15+rbx*4]
    mov edx, 10
    call .Lprint
    xor edi, edi
    jmp .Lexit

# Return validated string length. Linux execve limits bound all size arithmetic.
.Ldigits:
    xor eax, eax
.Lvalidate:
    movzx edx, byte ptr [rdi+rax]
    test edx, edx
    jz .Ldigits_end
    sub edx, '0'
    cmp edx, 9
    ja .Linvalid
    inc rax
    jmp .Lvalidate
.Ldigits_end:
    test rax, rax
    jz .Linvalid
    ret

# Parse decimal in chunks of eight, walking the groups from right to left.
.Lparse:
    xor r8d, r8d
.Lgroup:
    mov r9, rcx
    sub rcx, 8
    jae .Lgroup_start
    xor ecx, ecx
.Lgroup_start:
    mov r10, rcx
    xor eax, eax
.Linput_digit:
    imul rax, rax, 10
    movzx edx, byte ptr [rsi+r10]
    sub edx, '0'
    add rax, rdx
    inc r10
    cmp r10, r9
    jb .Linput_digit
    inc r8
    mov [rdi+r8*8], rax
    test rcx, rcx
    jnz .Lgroup
.Lskip_zero:
    test r8, r8
    jz .Lparsed
    cmp qword ptr [rdi+r8*8], 0
    jne .Lparsed
    dec r8
    jmp .Lskip_zero
.Lparsed:
    mov [rdi], r8
    ret

# Format rdi at rsi with suffix dl. Each significant limb contributes eight
# digits except the leading limb. Skip its padding before writing.
.Lprint:
    mov r11b, dl
    mov r8, [rdi]
    mov rcx, rsi
    test r8, r8
    jnz .Lnonzero
    mov byte ptr [rcx], '0'
    inc rcx
    jmp .Lsuffix
.Lnonzero:
    mov r10d, 10
.Loutput_group:
    mov rax, [rdi+r8*8]
    mov r9d, 8
.Loutput_digit:
    xor edx, edx
    div r10
    add dl, '0'
    dec r9
    mov [rcx+r9], dl
    jne .Loutput_digit
    add rcx, 8
    dec r8
    jnz .Loutput_group
.Lleading:
    cmp byte ptr [rsi], '0'
    jne .Lsuffix
    inc rsi
    jmp .Lleading
.Lsuffix:
    mov [rcx], r11b
    lea rdx, [rcx+1]
    sub rdx, rsi
    mov edi, 1
.Lwrite:
    mov eax, 1
    syscall
    cmp rax, -4
    je .Lwrite
    test rax, rax
    jle .Lwrite_error
    add rsi, rax
    sub rdx, rax
    jnz .Lwrite
    ret
.Lusage:
    lea rsi, [rip+.Lhelp]
    mov edx, HELP_LEN
    jmp .Lreport
.Linvalid:
    lea rsi, [rip+.Lbad]
    mov edx, BAD_LEN
    jmp .Lreport
.Lno_mem:
    lea rsi, [rip+.Lmem]
    mov edx, MEM_LEN
    jmp .Lreport
.Lwrite_error:
    lea rsi, [rip+.Lio]
    mov edx, IO_LEN
.Lreport:
    mov eax, 1
    mov edi, 2
    syscall
    mov edi, 2
.Lexit:
    mov eax, 60
    syscall
.section .note.GNU-stack,"",@progbits
