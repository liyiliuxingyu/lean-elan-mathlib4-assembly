# SPDX-License-Identifier: Apache-2.0 OR MIT
.intel_syntax noprefix

.macro parse_case value, kind, first_len=0, second_start=0, second_len=0
    .pushsection .rodata.parse_inputs,"a",@progbits
.Lp_input\@:
    .ascii "\value"
.Lp_end\@:
    .popsection
    .quad .Lp_input\@, .Lp_end\@ - .Lp_input\@
    .quad \kind, \first_len, \second_start, \second_len
.endm

.macro decode_case value, expected, capacity, result
    .pushsection .rodata.decode_inputs,"a",@progbits
.Ld_input\@:
    .ascii "\value"
.Ld_end\@:
.Ld_expected\@:
    .ascii "\expected"
    .popsection
    .quad .Ld_input\@, .Ld_end\@ - .Ld_input\@
    .quad .Ld_expected\@, \capacity, \result
.endm

.section .rodata
.balign 8
.Lparse_cases:
    parse_case "", 0
    parse_case "my-toolchain", 1, 12
    parse_case "stable", 1, 6
    parse_case "A-0.z", 1, 5
    parse_case ".", 1, 1
    parse_case "my_toolchain", 0
    parse_case "leanprover/lean4:v4.3.0", 2, 16, 17, 6
    parse_case "my_org/my_repo:v1.0.0", 2, 14, 15, 6
    parse_case "_/-:.", 2, 3, 4, 1
    parse_case "an.owner/repo:v1", 0
    parse_case "anOwner/a.repo:v1", 0
    parse_case "anOwner/repo:v_1", 0
    parse_case "owner/:v1", 0
    parse_case "owner/repo:", 0
    parse_case "owner/repo", 0
    parse_case "owner:repo", 0
    parse_case "owner/repo:v1:v2", 0
    parse_case "owner/repo:v1/other", 0
    parse_case "owner/repo:v1+", 0
    parse_case "owner/repo:v1\n", 0
    parse_case "not valid!", 0
    parse_case "rélease", 0
    parse_case "/", 3, 1
    parse_case "/opt/lean", 3, 9
    parse_case "/目录/lean:4", 3, 14
.Lparse_end:

.Ldecode_cases:
    decode_case "", "", 0, 0
    decode_case "leanprover--lean4---v4.3.0", "leanprover/lean4:v4.3.0", 23, 23
    decode_case "aa-bb--cc---dd", "aa-bb/cc:dd", 11, 11
    decode_case "----", ":-", 2, 2
    decode_case "-----", ":/", 2, 2
    decode_case "------", "::", 2, 2
    decode_case "-------", "::-", 3, 3
    decode_case "--------", "::/", 3, 3
    decode_case "-------", "", 2, -1
    decode_case "a", "", 0, -1
.Ldecode_end:

.Ldir_input:
    .ascii "leanprover--lean4---v4.3.0"
.Ldir_input_end:

.Lpass:
    .ascii "elan descriptor tests passed\n"
.Lpass_end:

.Lfail:
    .ascii "elan descriptor tests failed\n"
.Lfail_end:

.text
.globl _start
.type _start, @function
_start:
    sub rsp, 80
    lea rbx, [rip + .Lparse_cases]
    lea r12, [rip + .Lparse_end]

.Ltest_parse:
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    mov rdx, rsp
    call elan_parse_resolved
    cmp rax, [rbx + 16]
    jne .Ltest_fail
    cmp rax, [rsp]
    jne .Ltest_fail
    mov rdx, [rbx + 24]
    cmp rdx, [rsp + 16]
    jne .Ltest_fail
    xor edi, edi
    test rax, rax
    cmovne rdi, [rbx]
    cmp rdi, [rsp + 8]
    jne .Ltest_fail
    mov rdx, [rbx + 40]
    cmp rdx, [rsp + 32]
    jne .Ltest_fail
    xor edi, edi
    cmp eax, 2
    jne .Lcheck_second
    mov rdi, [rbx]
    add rdi, [rbx + 32]

.Lcheck_second:
    cmp rdi, [rsp + 24]
    jne .Ltest_fail
    add rbx, 48
    cmp rbx, r12
    jb .Ltest_parse

    lea rbx, [rip + .Ldecode_cases]
    lea r12, [rip + .Ldecode_end]

.Ltest_decode:
    mov rdi, rsp
    mov rsi, [rbx]
    mov rcx, [rbx + 8]
    rep movsb
    mov rdi, rsp
    mov rsi, [rbx + 8]
    mov rdx, rsp
    mov rcx, [rbx + 24]
    call elan_decode_toolchain_dir
    cmp rax, [rbx + 32]
    jne .Ltest_fail
    test rax, rax
    jle .Lnext_decode
    mov rdi, rsp
    mov rsi, [rbx + 16]
    mov rcx, rax
    repe cmpsb
    jne .Ltest_fail

.Lnext_decode:
    add rbx, 40
    cmp rbx, r12
    jb .Ltest_decode

    # Test the combined operation and the lifetime of returned slices.
    lea rdi, [rip + .Ldir_input]
    mov esi, .Ldir_input_end - .Ldir_input
    mov rdx, rsp
    mov ecx, 23
    lea r8, [rsp + 40]
    call elan_parse_toolchain_dir
    cmp rax, 2
    jne .Ltest_fail
    cmp QWORD PTR [rsp + 40], 2
    jne .Ltest_fail
    cmp [rsp + 48], rsp
    jne .Ltest_fail
    cmp QWORD PTR [rsp + 56], 16
    jne .Ltest_fail
    lea rax, [rsp + 17]
    cmp [rsp + 64], rax
    jne .Ltest_fail
    cmp QWORD PTR [rsp + 72], 6
    jne .Ltest_fail

    lea rdi, [rip + .Ldir_input]
    mov esi, .Ldir_input_end - .Ldir_input
    mov rdx, rsp
    mov ecx, 22
    lea r8, [rsp + 40]
    call elan_parse_toolchain_dir
    cmp rax, -1
    jne .Ltest_fail
    cmp QWORD PTR [rsp + 40], 2
    jne .Ltest_fail

    mov eax, 1
    mov edi, 1
    lea rsi, [rip + .Lpass]
    mov edx, .Lpass_end - .Lpass
    syscall
    xor edi, edi
    jmp .Ltest_exit

.Ltest_fail:
    mov eax, 1
    mov edi, 2
    lea rsi, [rip + .Lfail]
    mov edx, .Lfail_end - .Lfail
    syscall
    mov edi, 1

.Ltest_exit:
    mov eax, 60
    syscall
.size _start, .-_start

.section .note.GNU-stack,"",@progbits
