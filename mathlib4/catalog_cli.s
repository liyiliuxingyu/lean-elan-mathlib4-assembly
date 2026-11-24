# SPDX-License-Identifier: Apache-2.0
.intel_syntax noprefix
.include "catalog_layout.inc"
.include "olean_layout.inc"
.section .rodata
.Lbuild: .asciz "build"
.Llookup: .asciz "lookup"
.Lterm: .asciz "term"
.Lstats: .asciz "stats"
.Lusage: .asciz "usage: mathlib-catalog build INDEX ARCHIVE...\n       mathlib-catalog lookup INDEX NAME...\n       mathlib-catalog term INDEX THEOREM\n       mathlib-catalog stats INDEX\n"
.Lbuild_error: .asciz "mathlib-catalog: cannot create or replace index: "
.Larchive_error: .asciz "mathlib-catalog: unreadable or invalid module archive: "
.Lindex_error: .asciz "mathlib-catalog: invalid or unreadable index: "
.Lname_error: .asciz "mathlib-catalog: invalid qualified name: "
.Lchanged: .asciz "mathlib-catalog: archive differs from indexed snapshot: "
.Lnot_theorem: .asciz "mathlib-catalog: declaration is not a theorem: "
.Lterm_error: .asciz "mathlib-catalog: cannot read indexed theorem: "
.Lout_error: .asciz "mathlib-catalog: failed to write output\n"
.Lalloc_error: .asciz "mathlib-catalog: cannot allocate query workspace\n"
.Ltabs: .ascii "\t\n"
.Ldigits: .ascii "0123456789abcdef"
.Lstat_modules: .asciz "archives\t"
.Lstat_records: .asciz "declarations\t"
.Lstat_skipped: .asciz "unqueryable\t"
.Lmissing: .asciz "missing\t"
.balign 4
.Llabels: .long .Laxiom-.Llabels,.Ldef-.Llabels,.Lthm-.Llabels,.Lopaque-.Llabels
          .long .Lquot-.Llabels,.Lind-.Llabels,.Lctor-.Llabels,.Lrec-.Llabels
.Laxiom: .asciz "axiom\t"
.Ldef: .asciz "definition\t"
.Lthm: .asciz "theorem\t"
.Lopaque: .asciz "opaque\t"
.Lquot: .asciz "quotient\t"
.Lind: .asciz "inductive\t"
.Lctor: .asciz "constructor\t"
.Lrec: .asciz "recursor\t"
.bss
.balign 8
.Lcat: .skip V_BYTES
.Lmapping: .skip 8
.Lsize: .skip 8
.Lquery: .skip A_BYTES
.Lshort_key: .skip 2048
.Lpath: .skip 8
.Lpathlen: .skip 8
.Lhash: .skip 8
.Lmodule: .skip VIEW_BYTES
.Lresult: .skip RESULT_BYTES
.Lused: .skip 8
.Lbuffer: .skip 8192
.text
.globl _start
.type _start, @function
_start:
    mov rbp, rsp
    cmp qword ptr [rbp], 3
    jb .Lbad_usage
    mov rdi, [rbp+16]
    lea rsi, [rip+.Lbuild]
    call .Leq
    test eax, eax
    jz .Lread
    mov rsi, [rbp]
    sub rsi, 3
    jz .Lbad_usage
    mov rdi, [rbp+24]
    lea rdx, [rbp+32]
    call catalog_build
    test eax, eax
    jz .Lsuccess
    cmp eax, -2
    je .Lbad_archive
    mov rbx, [rbp+24]
    lea rdi, [rip+.Lbuild_error]
    jmp .Ldiagnose
.Lbad_archive:
    mov rbx, rdx
    lea rdi, [rip+.Larchive_error]
    jmp .Ldiagnose
.Lread:
    mov rdi, [rbp+16]
    lea rsi, [rip+.Lstats]
    call .Leq
    mov r15d, 2
    test eax, eax
    jz .Ltryterm
    cmp qword ptr [rbp], 3
    jne .Lbad_usage
    jmp .Lopen
.Ltryterm:
    mov rdi, [rbp+16]
    lea rsi, [rip+.Lterm]
    call .Leq
    mov r15d, 1
    test eax, eax
    jz .Ltrylookup
    cmp qword ptr [rbp], 4
    jne .Lbad_usage
    jmp .Lopen
.Ltrylookup:
    cmp qword ptr [rbp], 4
    jb .Lbad_usage
    mov rdi, [rbp+16]
    lea rsi, [rip+.Llookup]
    call .Leq
    test eax, eax
    jz .Lbad_usage
    xor r15d, r15d
.Lopen:
    mov rdi, [rbp+24]
    lea rsi, [rip+.Lmapping]
    lea rdx, [rip+.Lsize]
    call mathlib_ltar_map
    test eax, eax
    jnz .Lbad_index
    mov rdi, [rip+.Lmapping]
    mov rsi, [rip+.Lsize]
    lea rdx, [rip+.Lcat]
    call catalog_view
    test eax, eax
    jnz .Lbad_index
    cmp r15d, 2
    je .Lshow_stats
    mov r13, [rbp]
    sub r13, 3
    lea r12, [rbp+32]
    xor r14d, r14d                   # exit 1 if any name missing
.Lnext:
    # Common names fit in the static buffer and need one parse. Reuse larger
    # storage for the rest of the batch after the first exceptionally long key.
    mov rbx, [rip+.Lquery+A_DATA]
    mov rdx, [rip+.Lquery+A_CAP]
    test rbx, rbx
    jnz .Lencode
    lea rbx, [rip+.Lshort_key]
    mov edx, 2048
.Lencode:
    mov rdi, [r12]
    mov rsi, rbx
    call catalog_key_query
    cmp rax, -2
    jne .Lencoded
    mov rdi, [r12]
    xor esi, esi
    xor edx, edx
    call catalog_key_query
    test rax, rax
    jle .Lbad_name
    mov qword ptr [rip+.Lquery+A_USED], 0
    lea rdi, [rip+.Lquery]
    mov rsi, rax
    call catalog_extend
    test rax, rax
    jz .Lnomem
    mov rbx, rax
    mov rdx, [rip+.Lquery+A_CAP]
    jmp .Lencode
.Lencoded:
    test rax, rax
    jle .Lbad_name
    lea rdi, [rip+.Lcat]
    mov rsi, rbx
    mov rdx, rax
    call catalog_find
    test eax, eax
    js .Lbad_index
    jz .Lnotfound
    mov [rip+.Lpath], rdx
    mov [rip+.Lpathlen], rcx
    mov [rip+.Lhash], r9
    test r15d, r15d
    jnz .Lread_term
    lea rdi, [rip+.Llabels]
    movsxd rax, dword ptr [rdi+r8*4]
    add rdi, rax
    call .Lstring
    mov rdi, [r12]
    call .Lstring
    lea rdi, [rip+.Ltabs]
    mov esi, 1
    call .Lput
    mov rdi, [rip+.Lpath]
    mov rsi, [rip+.Lpathlen]
    call .Lescape
    jmp .Lrow_end
.Lnotfound:
    mov r14d, 1
    lea rdi, [rip+.Lmissing]
    call .Lstring
    mov rdi, [r12]
    call .Lstring
.Lrow_end:
    call .Lnewline
    add r12, 8
    dec r13
    jnz .Lnext
    call .Lflush
    mov edi, r14d
    jmp .Lexit
.Lread_term:
    cmp r8d, 2
    jne .Lbad_term_kind
    mov rdi, [rip+.Lpath]
    lea rsi, [rip+.Lmodule]
    lea rdx, [rip+.Lsize]            # available after catalog validation
    call catalog_open_module
    mov rbx, [rip+.Lpath]
    test eax, eax
    jnz .Lopen_error
    mov rax, [rip+.Lsize]
    cmp rax, [rip+.Lhash]
    jne .Lstale
    lea rdi, [rip+.Lmodule]
    mov rsi, [r12]
    lea rdx, [rip+.Lresult]
    call mathlib_olean_lookup
    cmp eax, 1
    jne .Lbroken_term
    cmp qword ptr [rip+.Lresult+RESULT_KIND], 2
    jne .Lbroken_term
    lea rdi, [rip+.Lmodule]
    mov rsi, [rip+.Lresult+RESULT_TYPE]
    mov rdx, [rip+.Lresult+RESULT_PROOF]
    call mathlib_olean_dump_term
    test eax, eax
    jz .Lsuccess
    cmp eax, -2
    je .Loutput_error
.Lbroken_term:
    mov rbx, [r12]
    lea rdi, [rip+.Lterm_error]
    jmp .Ldiagnose
.Lopen_error:
    lea rdi, [rip+.Larchive_error]
    jmp .Ldiagnose
.Lstale:
    lea rdi, [rip+.Lchanged]
    jmp .Ldiagnose
.Lbad_term_kind:
    mov rbx, [r12]
    lea rdi, [rip+.Lnot_theorem]
    jmp .Ldiagnose
.Lshow_stats:
    mov rbx, [rip+.Lcat+V_HEADER]
    lea rdi, [rip+.Lstat_modules]
    call .Lstring
    mov rax, [rbx+H_MODULES]
    call .Lprint_count
    lea rdi, [rip+.Lstat_records]
    call .Lstring
    mov rax, [rbx+H_RECORDS]
    call .Lprint_count
    lea rdi, [rip+.Lstat_skipped]
    call .Lstring
    mov rax, [rbx+H_SKIPPED]
    call .Lprint_count
    call .Lflush
.Lsuccess:
    xor edi, edi
.Lexit:
    mov eax, 60
    syscall
.Lbad_index:
    mov rbx, [rbp+24]
    lea rdi, [rip+.Lindex_error]
    jmp .Ldiagnose
.Lbad_name:
    mov rbx, [r12]
    lea rdi, [rip+.Lname_error]
.Ldiagnose:
    call .Lflush
    call .Lstderr
    mov rdi, rbx
    call .Lstderr
    lea rsi, [rip+.Ltabs+1]
    mov edx, 1
    mov edi, 2
    call catalog_write
    jmp .Lerror_exit
.Lbad_usage:
    lea rdi, [rip+.Lusage]
    jmp .Lfatal
.Lnomem:
    lea rdi, [rip+.Lalloc_error]
    jmp .Lfatal
.Loutput_error:
    lea rdi, [rip+.Lout_error]
.Lfatal:
    call .Lstderr
.Lerror_exit:
    mov edi, 2
    jmp .Lexit

.Leq:
    mov al, [rdi]
    inc rdi
    cmp al, [rsi]
    jne .Lneq
    inc rsi
    test al, al
    jnz .Leq
    mov eax, 1
    ret
.Lneq:
    xor eax, eax
    ret
.Llen:
    mov rax, rdi
.Lstrlen:
    cmp byte ptr [rax], 0
    je .Llength
    inc rax
    jmp .Lstrlen
.Llength:
    sub rax, rdi
    ret
.Lstderr:
    call .Llen
    mov rdx, rax
    mov rsi, rdi
    mov edi, 2
    jmp catalog_write
.Lstring:
    call .Llen
    mov rsi, rax
    jmp .Lput
.Lprint_count:
    sub rsp, 40
    lea rdi, [rsp+40]
    mov r8d, 10
.Ldigit:
    xor edx, edx
    div r8
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .Ldigit
    lea rsi, [rsp+40]
    sub rsi, rdi
    call .Lput
    add rsp, 40
.Lnewline:
    lea rdi, [rip+.Ltabs+1]
    mov esi, 1
.Lput:
    # Append (rdi,rsi); output is buffered across names.
    test rsi, rsi
    jz .Lput_done
    mov r9, [rip+.Lused]
    mov ecx, 8192
    sub rcx, r9
    jnz .Lcopy
    push rdi
    push rsi
    call .Lflush
    pop rsi
    pop rdi
    jmp .Lput
.Lcopy:
    cmp rcx, rsi
    cmova rcx, rsi
    add [rip+.Lused], rcx
    lea rax, [rip+.Lbuffer]
    mov r8, rsi
    sub r8, rcx
    mov rsi, rdi
    lea rdi, [rax+r9]
    rep movsb
    mov rdi, rsi
    mov rsi, r8
    jmp .Lput
.Lput_done:
    ret
.Lflush:
    push rdi
    mov edi, 1
    lea rsi, [rip+.Lbuffer]
    mov rdx, [rip+.Lused]
    call catalog_write
    pop rdi
    test eax, eax
    jnz .Loutput_error
    mov qword ptr [rip+.Lused], 0
    ret

# Escape control bytes and backslashes in an archive path printed as TSV.
.Lescape:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r12, rdi
    lea r13, [rdi+rsi]
.Lescscan:
    cmp rbx, r13
    je .Lesclast
    movzx eax, byte ptr [rbx]
    cmp al, 32
    jb .Lescape_one
    cmp al, 127
    je .Lescape_one
    cmp al, 92
    je .Lescape_one
    inc rbx
    jmp .Lescscan
.Lescape_one:
    mov rdi, r12
    mov rsi, rbx
    sub rsi, r12
    call .Lput
    movzx eax, byte ptr [rbx]
    mov edx, eax
    shr eax, 4
    and edx, 15
    lea rdi, [rip+.Ldigits]
    mov al, [rdi+rax]
    mov dl, [rdi+rdx]
    mov word ptr [rsp], 0x785c
    mov [rsp+2], al
    mov [rsp+3], dl
    mov rdi, rsp
    mov esi, 4
    call .Lput
    inc rbx
    mov r12, rbx
    jmp .Lescscan
.Lesclast:
    mov rdi, r12
    mov rsi, rbx
    sub rsi, r12
    call .Lput
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
.size _start, .-_start
.section .note.GNU-stack,"",@progbits
