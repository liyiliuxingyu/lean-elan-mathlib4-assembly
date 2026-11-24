# SPDX-License-Identifier: Apache-2.0
# Dictionary/window boundaries, crossing from dictionary to frame history,
# overlapping matches, state reuse, and the zero-literal repeat-offset rule.
.intel_syntax noprefix
.section .rodata
.Ldict:
    .ascii "abcdefgh"
.Lraw:
    .ascii "WXYZ"
.Lexpected:
    .ascii "WXYZhWXZhW"
.Lformal:
    .long 0xec30a437, 42
    .byte 0x80, 0x10               # two equal Huffman weights
    .rept 3
    .byte 0x10, 0x3f               # FSE probabilities {16,16}
    .endr
    .long 1,4,8
    .ascii "abcdefgh"
.Lformal_end:
.Lno_id:
    .long 0xec30a437, 0
    .byte 0x80, 0x10
    .rept 3
    .byte 0x10, 0x3f
    .endr
    .long 1,4,8
    .ascii "abcdefgh"
.Lno_id_end:
.Ldict_start:
    .byte 1, 0x54, 0,3,0, 0x0b     # LL=0, OF=3, ML=0; distance 8, length 3
.Ldict_cross:
    .byte 1, 0x54, 0,3,0, 0x08     # distance 5
.Ldict_past:
    .byte 1, 0x54, 0,3,0, 0x09     # distance 6
.Lrep_minus_one:
    .byte 1, 0xdc, 1, 0x03         # reuse LL and ML; rep1 minus one
.Lrepeat_previous:
    .byte 1, 0xfc, 0x03            # reuse all tables
.Lrepeat_one:
    .byte 1, 0x54, 1,0,4, 1        # one literal; rep1=1, length 7
.Lletter:
    .ascii "Q"

.bss
.p2align 3
.Lctx: .skip 32768
.Lout: .skip 24

.text
.globl _start
.type _start,@function
_start:
    lea rdi,[rip+.Lctx]
    lea rsi,[rip+.Lformal]
    mov edx,.Lformal_end-.Lformal
    mov ecx,4
    call z6_entropy_init
    test eax,eax
    jne .Lfail
    lea rdi,[rip+.Lctx]
    lea rsi,[rip+.Lno_id]
    mov edx,.Lno_id_end-.Lno_id
    mov ecx,4
    call z6_entropy_init
    cmp eax,-1
    jne .Lfail

    call .Lreset
    # The oldest dictionary byte is available even beyond the 4-byte window.
    lea rsi,[rip+.Ldict_start]
    mov edx,6
    xor eax,eax                    # prior output
    call .Lrun
    cmp rax,3
    jne .Lfail
    cmp word ptr [rip+.Lout],0x6261
    jne .Lfail
    cmp byte ptr [rip+.Lout+2],'c'
    jne .Lfail

    call .Lreset
    mov eax,[rip+.Lraw]
    mov [rip+.Lout],eax
    lea rsi,[rip+.Ldict_cross]
    mov edx,6
    mov eax,4                      # history exactly fills the window
    call .Lrun
    cmp rax,3
    jne .Lfail
    lea rsi,[rip+.Lrep_minus_one]
    mov edx,4
    mov eax,7
    call .Lrun
    cmp rax,3
    jne .Lfail
    lea rsi,[rip+.Lout]
    lea rdi,[rip+.Lexpected]
    mov ecx,10
    repe cmpsb
    jne .Lfail

    call .Lreset
    lea rsi,[rip+.Ldict_past]
    mov edx,6
    mov eax,5                      # dictionary is no longer in history
    call .Lrun
    cmp rax,-1
    jne .Lfail
    call .Lreset
    lea rsi,[rip+.Lrepeat_previous]
    mov edx,3
    xor eax,eax
    call .Lrun
    cmp rax,-1                     # no preceding sequence tables
    jne .Lfail

    # A distance-1 copy may read bytes produced by the same match.
    call .Lreset
    lea rdi,[rip+.Lctx]
    lea rsi,[rip+.Lrepeat_one]
    mov edx,6
    lea rcx,[rip+.Lletter]
    mov r8d,1
    lea r9,[rip+.Lout]
    push 8
    push 0
    call z6_sequences
    add rsp,16
    cmp rax,8
    jne .Lfail
    movabs rax,0x5151515151515151
    cmp [rip+.Lout],rax
    jne .Lfail
    xor edi,edi
    jmp .Lexit
.Lfail:
    mov edi,1
.Lexit:
    mov eax,60
    syscall

# Helpers below arrange the SysV stack alignment and two stack arguments.
.Lreset:
    lea rdi,[rip+.Lctx]
    lea rsi,[rip+.Ldict]
    mov edx,8
    mov ecx,4
    jmp z6_entropy_init
.Lrun:
    lea rdi,[rip+.Lctx]
    lea rcx,[rip+.Lletter]
    xor r8d,r8d
    lea r9,[rip+.Lout]
    sub rsp,8
    push 24
    push rax
    call z6_sequences
    add rsp,24
    ret
.size _start,.-_start
.section .note.GNU-stack,"",@progbits
