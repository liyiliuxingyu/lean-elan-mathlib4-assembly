/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Shared byte, pathname and environment operations for Linux process entry points. */
.intel_syntax noprefix
.text
.globl elan_strlen, elan_join_component, elan_append_z, elan_read_u32
/* rdi = NUL-terminated input; rax = length. */
elan_strlen:
    xor     eax, eax
.Lstrlen_byte:
    cmp     byte ptr [rdi+rax], 0
    je      .Lstrlen_done
    inc     rax
    jmp     .Lstrlen_byte
.Lstrlen_done:
    ret

/* Append a NUL-terminated component, adding a separator when needed. */
elan_join_component:
    cmp     byte ptr [rsi], 0
    je      elan_append_z
    cmp     byte ptr [rdi-1], '/'
    je      elan_append_z
    cmp     rdi, rdx
    jae     .Lappend_full
    mov     byte ptr [rdi], '/'
    inc     rdi
/* rdi = destination cursor; rsi = source; rdx = destination bound.
 * On success rdi points to the terminating NUL and CF is clear.
 */
elan_append_z:
    cmp     rdi, rdx
    jae     .Lappend_full
    lodsb
    mov     [rdi], al
    test    al, al
    jz      .Lappend_done
    inc     rdi
    jmp     elan_append_z
.Lappend_done:
    clc
    ret
.Lappend_full:
    stc
    ret

/* Optional + followed by decimal digits in u32 range. Invalid input is 0. */
elan_read_u32:
    xor     eax, eax
    test    rsi, rsi
    jz      .Lu32_done
    cmp     byte ptr [rsi], '+'
    jne     .Lu32_digit
    inc     rsi
.Lu32_digit:
    movzx   ecx, byte ptr [rsi]
    test    ecx, ecx
    jz      .Lu32_done
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .Lu32_invalid
    imul    rax, rax, 10
    add     rax, rcx
    mov     rcx, rax
    shr     rcx, 32
    jnz     .Lu32_invalid
    inc     rsi
    jmp     .Lu32_digit
.Lu32_invalid:
    xor     eax, eax
.Lu32_done:
    ret


/* Append a descriptor as one filename component. The caller supplies the
 * separator. As for elan_append_z, rdi ends at NUL and CF reports overflow. */
.globl elan_append_encoded
elan_append_encoded:
    lodsb
    mov ecx, 1
    cmp al, '/'
    je .Lpair
    cmp al, ':'
    jne .Lemit
    inc ecx
.Lpair:
    inc ecx
    mov al, '-'
.Lemit:
    cmp rdi, rdx
    jae .Lappend_full
    mov [rdi], al
    test al, al
    jz .Lappend_done
    inc rdi
    dec ecx
    jnz .Lemit
    jmp elan_append_encoded

/* Copy rsi to the bounded rdi..rdx buffer, relative to the current directory.
 * On success eax = 0 and rdi is the NUL cursor. Errors match elan_home_path. */
.globl elan_absolute
elan_absolute:
    cmp byte ptr [rsi], '/'
    je .Labsolute_copy
    push rsi
    mov rsi, rdx
    sub rsi, rdi
    mov eax, 79                    /* getcwd includes NUL in its count */
    syscall
    pop rsi
    test rax, rax
    js .Lcwd_error
    lea rdi, [rdi+rax-1]
    call elan_join_component
    jmp .Labsolute_return
.Labsolute_copy:
    call elan_append_z
.Labsolute_return:
    jc .Ltoo_long
    xor eax, eax
    ret
.Lcwd_error:
    mov eax, 2
    ret
.Ltoo_long:
    mov eax, 3
    ret

/* (ELAN_HOME or NULL, HOME or NULL, buffer of 4096 bytes).
 * EAX = 0 on success, 1 if neither home is set, 2 on getcwd, 3 on overflow. */
.globl elan_home_path
elan_home_path:
    mov r8, rdi
    test rdi, rdi
    jz .Lfrom_user_home
    mov rsi, rdi
    jmp .Lresolve_home
.Lfrom_user_home:
    test rsi, rsi
    jz .Lno_home
    cmp byte ptr [rsi], 0
    je .Lno_home
.Lresolve_home:
    mov rdi, rdx
    add rdx, 4096
    call elan_absolute
    test eax, eax
    jnz .Lhome_done
    test r8, r8
    jnz .Lhome_done
    lea rsi, [rip+.Ldot_elan]
    call elan_join_component
    jc .Ltoo_long
    xor eax, eax
.Lhome_done:
    ret
.Lno_home:
    mov eax, 1
    ret

.section .rodata
.Ldot_elan: .asciz ".elan"
.section .note.GNU-stack,"",@progbits
