/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Writable fixtures because the parser decodes and terminates strings in place. */
.intel_syntax noprefix
.section .data
.Ltypical: .asciz "default_toolchain = \"leanprover/lean4:v4.19.0\"\ntelemetry = false\nversion = \"12\"\n\n[overrides]\n"
.Lsingle:  .asciz " version='2'  # old format\r\ndefault_toolchain = 'path # here'\r\n"
.Lescaped: .asciz "version=\"12\"\ndefault_toolchain=\"a\\\\b\\\"c\""
.Lnone:    .asciz "version=\"12\"\n# no default\n[ overrides ]"
.Lempty:   .asciz "default_toolchain=''\nversion='2'"
.Linvalid_version: .asciz "version='22'"
.Lmissing_version: .asciz "default_toolchain='stable'"
.Lduplicate:       .asciz "version='12'\ndefault_toolchain='a'\ndefault_toolchain='b'"
.Ltype:            .asciz "version='12'\ndefault_toolchain=true"
.Loverrides:       .asciz "version='12'\n[overrides]\n'/tmp'='abc'"
.Ltelemetry:       .asciz "version='12'\ntelemetry='false'"
.Lmultiline:       .asciz "version='12'\ndefault_toolchain='a\nb'"
.Lescape:          .asciz "version='12'\ndefault_toolchain=\"bad\\z\""

.section .rodata
.Ls1: .asciz "leanprover/lean4:v4.19.0"
.Ls2: .asciz "path # here"
.Ls3: .asciz "a\\b\"c"
.Ls4: .asciz ""
.balign 8
.Lcases:
.quad .Ltypical, .Ls1, .Lsingle, .Ls2, .Lescaped, .Ls3, .Lnone, 0, .Lempty, .Ls4
.quad .Linvalid_version, -1, .Lmissing_version, -1, .Lduplicate, -1, .Ltype, -1
.quad .Loverrides, 0, .Ltelemetry, -1, .Lmultiline, -1, .Lescape, -1
.Lend:

.section .text
.globl _start
_start:
    lea     r12, [rip+.Lcases]
    lea     r13, [rip+.Lend]
.Lcase:
    mov     rdi, [r12]
    call    elan_settings_default
    mov     rsi, [r12+8]
    cmp     rsi, -1
    je      .Lsentinel
    test    rsi, rsi
    jz      .Lsentinel
    cmp     rax, -1
    je      .Lfail
    test    rax, rax
    jz      .Lfail
    mov     rdi, rax
.Lcompare:
    lodsb
    scasb
    jne     .Lfail
    test    al, al
    jnz     .Lcompare
    jmp     .Lnext
.Lsentinel:
    cmp     rax, rsi
    jne     .Lfail
.Lnext:
    add     r12, 16
    cmp     r12, r13
    jb      .Lcase
    xor     edi, edi
    jmp     .Lexit
.Lfail:
    mov     edi, 1
.Lexit:
    mov     eax, 60
    syscall
.section .note.GNU-stack,"",@progbits
