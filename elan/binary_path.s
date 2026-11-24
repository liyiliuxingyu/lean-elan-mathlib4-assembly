/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Linux Toolchain::from and Toolchain::binary_file path construction. */
.intel_syntax noprefix
.text
/* rdi = buffer, rdx = end, rsi = home, r8 = descriptor, ecx = descriptor kind.
 * Result: NUL cursor in rdi, CF on overflow. */
.globl elan_toolchain_root
elan_toolchain_root:
    cmp ecx, 3
    jne .Lnamed
    mov rsi, r8
    jmp elan_append_z
.Lnamed:
    call elan_append_z
    jc .Lreturn
    lea rsi, [rip+.Ltoolchains]
    call elan_join_component
    jc .Lreturn
    lea rsi, [rip+.Lslash]
    call elan_append_z
    jc .Lreturn
    mov rsi, r8
    jmp elan_append_encoded

/* rdi = root NUL cursor, rdx = end, rsi = command, r8 = buffer start.
 * Linux has an empty executable suffix. A final component with an extension
 * preserves the original spelling of the entire command, including parents.
 * Rust Path::file_name skips embedded/trailing "." and separators. */
.globl elan_binary_file
elan_binary_file:
    push rbx
    mov rbx, rsi
    cmp byte ptr [rbx], '/'
    je .Lreplace
    lea rsi, [rip+.Lbin]
    call elan_join_component
    jc .Lpop
    /* Even joining the empty pathname appends a directory separator. */
    lea rsi, [rip+.Lslash]
    call elan_append_z
    jc .Lpop
    jmp .Lcopy
.Lreplace:
    mov rdi, r8
.Lcopy:
    mov r9, rdi
    mov rsi, rbx
    call elan_append_z
    jc .Lpop
    mov rcx, rdi
.Llast_component:
    cmp rcx, r9
    je .Lno_extension
    cmp byte ptr [rcx-1], '/'
    jne .Lcomponent
    dec rcx
    jmp .Llast_component
.Lcomponent:
    mov rsi, rcx
.Lbegin:
    cmp rsi, r9
    je .Lextension
    cmp byte ptr [rsi-1], '/'
    je .Lextension
    dec rsi
    jmp .Lbegin
.Lextension:
    mov rax, rcx
    sub rax, rsi
    cmp byte ptr [rsi], '.'
    jne .Ldot_search
    cmp eax, 1
    jne .Lparent
    mov rcx, rsi
    jmp .Llast_component
.Lparent:
    cmp eax, 2
    jne .Ldot_search
    cmp byte ptr [rsi+1], '.'
    je .Lno_extension
.Ldot_search:
    inc rsi
    cmp rsi, rcx
    jae .Lno_extension
    cmp byte ptr [rsi], '.'
    jne .Ldot_search
    jmp .Lok
.Lno_extension:
    mov rdi, r9
    mov rsi, rbx
    call elan_lower_into
    jmp .Lpop
.Lok:
    clc
.Lpop:
    pop rbx
.Lreturn:
    ret
.section .rodata
.Ltoolchains: .asciz "toolchains"
.Lbin: .asciz "bin"
.Lslash: .asciz "/"
.section .note.GNU-stack,"",@progbits
