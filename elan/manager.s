/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Linux x86-64 process entry point for Elan's two local toolchain commands. */
.intel_syntax noprefix
.equ CAP, 4096
.equ SYS_stat, 4
.equ SYS_lstat, 6
.equ SYS_mkdir, 83
.equ SYS_symlink, 88
.equ DIRECTORY, 0x4000
.equ REGULAR, 0x8000
.equ SYMLINK, 0xa000
.equ S_IFMT, 0xf000

.text
.globl _start
.type _start,@function
_start:
    mov r12, [rsp]
    lea r13, [rsp+8]
    lea r14, [r13+r12*8+8]
    cmp r12, 3
    jb .Lusage
    mov rdi, [r13+8]
    lea rsi, [rip+.Ltoolchain]
    call .Lmatches
    jne .Lusage
    mov rdi, [r13+16]
    lea rsi, [rip+.Llist]
    call .Lmatches
    jne .Llink_args
    cmp r12, 3
    jne .Lusage
    jmp .Lenvironment
.Llink_args:
    mov rdi, [r13+16]
    lea rsi, [rip+.Llink]
    call .Lmatches
    jne .Lusage
    cmp r12, 6
    jne .Lpositionals
    mov rdi, [r13+24]
    lea rsi, [rip+.Lend_options]
    call .Lmatches
    jne .Lusage
    add r13, 8
    jmp .Lsave_args
.Lpositionals:
    cmp r12, 5
    jne .Lusage
    mov rdi, [r13+24]
    call .Loption
    jc .Lusage
    mov rdi, [r13+32]
    call .Loption
    jc .Lusage
.Lsave_args:
    mov rbx, [r13+24]
    mov [rip+.Lname_arg], rbx
    mov r15, [r13+32]
    mov [rip+.Lroot_arg], r15
    mov rdi, rbx
    call .Lvalid_arg
    test eax, eax
    jz .Lbad_utf8
    mov rdi, r15
    call .Lvalid_arg
    test eax, eax
    jz .Lbad_utf8
.Lenvironment:
    mov rdi, [r14]
    test rdi, rdi
    jz .Lhome_path
    add r14, 8
    lea rbx, [rip+.Lvars]
.Lenv_match:
    mov rsi, [rbx]
    mov r8, rdi
    mov rcx, [rbx+8]
    repe cmpsb
    je .Lsave_env
    mov rdi, r8
    add rbx, 24
    cmp qword ptr [rbx], 0
    jne .Lenv_match
    jmp .Lenvironment
.Lsave_env:
    mov rax, [rbx+16]
    mov [rax], rdi
    jmp .Lenvironment
.Lhome_path:
    mov rsi, [rip+.Lrecursion]
    call elan_read_u32
    cmp eax, 5
    ja .Lrecursive
    mov rdi, [rip+.Lelan_home]
    mov rsi, [rip+.Luser_home]
    lea rdx, [rip+.Lhome]
    call elan_home_path
    test eax, eax
    jnz .Lbad_home
    lea rdi, [rip+.Lhome]
    call .Lmkdir_all
    test eax, eax
    js .Lcannot_home
    lea rdi, [rip+.Ldestination]
    lea rsi, [rip+.Lhome]
    lea rdx, [rip+.Ldestination+CAP]
    call elan_append_z
    jc .Ltoo_long
    lea rsi, [rip+.Ltoolchains]
    call elan_join_component
    jc .Ltoo_long
    mov r12, rdi                    /* trailing NUL, after toolchains */
    lea rdi, [rip+.Ldestination]
    cmp qword ptr [rip+.Lname_arg], 0
    jne .Llink_toolchain
    call elan_list_toolchains
    jmp .Lsuccess

.Llink_toolchain:
    call .Lmkdir_all
    test eax, eax
    js .Lcannot_toolchains

    /* Source diagnostics show the original spelling. Record the full
     * absolute symlink target separately, without following or normalizing it. */
    lea rdi, [rip+.Lprobe]
    lea rdx, [rip+.Lprobe+CAP]
    mov rsi, [rip+.Lroot_arg]
    call elan_append_z
    jc .Ltoo_long
    lea rsi, [rip+.Lbin]
    cmp rdi, OFFSET FLAT:.Lprobe   /* PathBuf::from("").push("bin") */
    jne .Ljoin_bin
    call elan_append_z
    jmp .Lprobe_bin
.Ljoin_bin:
    call elan_join_component
.Lprobe_bin:
    jc .Ltoo_long
    mov r15, rdi
    lea rdi, [rip+.Lprobe]
    call .Ltype
    cmp eax, DIRECTORY
    jne .Lmissing_bin
    mov rdi, r15
    lea rdx, [rip+.Lprobe+CAP]
    lea rsi, [rip+.Llean]
    call elan_join_component
    jc .Ltoo_long
    lea rdi, [rip+.Lprobe]
    call .Ltype
    cmp eax, REGULAR
    jne .Lmissing_lean
    lea rdi, [rip+.Ltarget]
    lea rdx, [rip+.Ltarget+CAP]
    mov rsi, [rip+.Lroot_arg]
    call elan_absolute
    test eax, eax
    jnz .Ltoo_long
    mov rsi, [rip+.Lroot_arg]
    cmp byte ptr [rsi], 0
    jne .Lbuild_dest
    cmp byte ptr [rdi-1], '/'
    je .Lbuild_dest
    lea rsi, [rip+.Lslash]
    call elan_append_z
    jc .Ltoo_long
.Lbuild_dest:
    mov rdi, r12
    lea rdx, [rip+.Ldestination+CAP]
    lea rsi, [rip+.Lslash]
    call elan_append_z
    jc .Ltoo_long
    mov rsi, [rip+.Lname_arg]
    call elan_append_encoded
    jc .Ltoo_long
    /* symlink(2) fails atomically if a destination exists. Never unlink
     * an existing object, including one installed by a concurrent process. */
    lea rdi, [rip+.Ltarget]
    lea rsi, [rip+.Ldestination]
    mov eax, SYS_symlink
    syscall
    test rax, rax
    jz .Lsuccess
    cmp eax, -17                    /* EEXIST */
    jne .Llink_error
    mov rdi, rsi
    lea rsi, [rip+.Lstat]
    mov eax, SYS_lstat
    syscall
    test rax, rax
    js .Llink_error
    mov eax, [rsi+24]
    and eax, S_IFMT
    cmp eax, SYMLINK
    je .Linstalled
    cmp eax, DIRECTORY
    je .Linstalled
    /* An ordinary file at the destination remains untouched in Elan too. */
    lea rdi, [rip+.Lcollision]
    lea rsi, [rip+.Ldestination]
    mov edx, -20                    /* ENOTDIR */
    jmp elan_manage_io_error
.Lsuccess:
    xor edi, edi
    jmp .Lexit

/* Return only the file type (follows links), or negative errno. */
.Ltype:
    lea rsi, [rip+.Lstat]
    mov eax, SYS_stat
    syscall
    test rax, rax
    js .Ltype_done
    mov eax, [rsi+24]
    and eax, S_IFMT
.Ltype_done:
    ret

/* mkdir -p. Preserve original path spelling on return. On existing dirs,
 * permission to create new siblings is not needed. */
.Lmkdir_all:
    push rbx
    push r12
    mov r12, rdi
    call .Ltype
    cmp eax, DIRECTORY
    je .Lmkdir_ok
    mov rbx, r12
.Lsegment:
    cmp byte ptr [rbx], '/'
    jne .Lwalk
    inc rbx
    jmp .Lsegment
.Lwalk:
    cmp byte ptr [rbx], 0
    je .Llast
    cmp byte ptr [rbx], '/'
    je .Lslash_dir
    inc rbx
    jmp .Lwalk
.Lslash_dir:
    mov byte ptr [rbx], 0
    mov rdi, r12
    call .Lmkdir
    mov byte ptr [rbx], '/'
    test eax, eax
    js .Lmkdir_return
    jmp .Lsegment
.Llast:
    mov rdi, r12
    call .Lmkdir
    jmp .Lmkdir_return
.Lmkdir_ok:
    xor eax, eax
.Lmkdir_return:
    pop r12
    pop rbx
    ret
.Lmkdir:
    mov esi, 0777
    mov eax, SYS_mkdir
    syscall
    cmp eax, -17                    /* directory may already exist */
    jne .Lmkdir_done
    call .Ltype
    cmp eax, DIRECTORY
    mov eax, -17
    jne .Lmkdir_done
    xor eax, eax
.Lmkdir_done:
    ret

/* Test NUL strings for equality. ZF reports the result. */
.Lmatches:
    lodsb
    cmp al, [rdi]
    jne .Lmatched
    inc rdi
    test al, al
    jne .Lmatches
.Lmatched:
    ret
.Loption:
    cmp byte ptr [rdi], '-'
    jne .Lpos
    cmp byte ptr [rdi+1], 0
    je .Lpos
    stc
    ret
.Lpos:
    clc
    ret
.Lvalid_arg:
    call elan_strlen
    mov rsi, rax
.globl elan_manage_utf8
elan_manage_utf8:
    sub rsp, 24
    mov qword ptr [rsp], 0
    mov qword ptr [rsp+8], 0
    mov rdx, rsp
    lea rcx, [rsp+8]
    call _ZN4lean13validate_utf8EPKhmRmS2_
    add rsp, 24
    ret

.Lmissing_bin:
    lea rdi, [rip+.Lnot_dir]
    jmp .Lprobe_error
.Lmissing_lean:
    lea rdi, [rip+.Lnot_file]
.Lprobe_error:
    lea rsi, [rip+.Lprobe]
    jmp .Lquoted_error
.Linstalled:
    lea rdi, [rip+.Linstalled_prefix]
    mov rsi, [rip+.Lname_arg]
    lea rdx, [rip+.Linstalled_suffix]
    jmp elan_manage_error
.Lquoted_error:
    lea rdx, [rip+.Lquote_end]
    jmp elan_manage_error
.Lbad_utf8:
    lea rsi, [rip+.Lutf8_error]
    jmp .Lone_error
.Lbad_home:
    lea rsi, [rip+.Lhome_error]
    jmp .Lone_error
.Ltoo_long:
    lea rsi, [rip+.Lpath_error]
    jmp .Lone_error
.Lrecursive:
    lea rsi, [rip+.Lrecursion_error]
    jmp .Lone_error
.Lusage:
    lea rsi, [rip+.Lusage_text]
.Lone_error:
    mov edi, 2
    call elan_manage_write
    jmp elan_manage_fail
.Lcannot_home:
    mov edx, eax
    lea rdi, [rip+.Lcreate_home]
    lea rsi, [rip+.Lhome]
    jmp elan_manage_io_error
.Lcannot_toolchains:
    mov edx, eax
    lea rdi, [rip+.Lcreate_toolchains]
    lea rsi, [rip+.Ldestination]
    jmp elan_manage_io_error
.Llink_error:
    mov ebx, eax
    mov edi, 2
    lea rsi, [rip+.Lcreate_link]
    call elan_manage_write
    mov edi, 2
    lea rsi, [rip+.Ltarget]
    call elan_manage_write
    lea rdi, [rip+.Lto]
    lea rsi, [rip+.Ldestination]
    mov edx, ebx
.globl elan_manage_io_error
elan_manage_io_error:
    mov ebx, edx
    mov r12, rsi
    mov rsi, rdi
    mov edi, 2
    call elan_manage_write
    mov rsi, r12
    call elan_manage_write
    lea rsi, [rip+.Lcause]
    call elan_manage_write
    neg ebx
    lea r12, [rip+.Lerrors]
.Lfind_errno:
    mov rsi, [r12+8]
    cmp dword ptr [r12], 0
    je .Lreason
    cmp ebx, [r12]
    je .Lreason
    add r12, 16
    jmp .Lfind_errno
.Lreason:
    call elan_manage_write
    lea rsi, [rip+.Los_error]
    call elan_manage_write
    lea rsi, [rip+.Lnumber+16]
    mov byte ptr [rsi], 0
    mov eax, ebx
    mov r8d, 10
.Ldecimal:
    xor edx, edx
    div r8d
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test eax, eax
    jne .Ldecimal
    call elan_manage_write
    lea rsi, [rip+.Lclose_paren]
    call elan_manage_write
    jmp elan_manage_fail

/* Prefix, name, suffix (all NUL-terminated). Exit with Elan's error status. */
.globl elan_manage_error
elan_manage_error:
    mov r12, rsi
    mov r13, rdx
    mov rsi, rdi
    mov edi, 2
    call elan_manage_write
    mov rsi, r12
    call elan_manage_write
    mov rsi, r13
    call elan_manage_write
.globl elan_manage_fail
elan_manage_fail:
    mov edi, 1
.Lexit:
    mov eax, 60
    syscall

/* (rdi = fd, rsi = NUL string). Leaves rdi intact. */
.globl elan_manage_write
elan_manage_write:
    xor edx, edx
.Lcount:
    cmp byte ptr [rsi+rdx], 0
    je .Lwrite
    inc rdx
    jmp .Lcount
.Lwrite:
    test rdx, rdx
    jz .Lwritten
    mov eax, 1
    syscall
    cmp rax, -4
    je .Lwrite
    test rax, rax
    jle elan_manage_fail
    add rsi, rax
    sub rdx, rax
    jmp .Lwrite
.Lwritten:
    ret

.section .rodata
.Ltoolchain: .asciz "toolchain"
.Ltoolchains: .asciz "toolchains"
.Llink: .asciz "link"
.Llist: .asciz "list"
.Lend_options: .asciz "--"
.Lbin: .asciz "bin"
.Llean: .asciz "lean"
.Lslash: .asciz "/"
.Lelan_var: .ascii "ELAN_HOME="
.Lhome_var: .ascii "HOME="
.Lrecursion_var: .ascii "LEAN_RECURSION_COUNT="
.balign 8
.Lvars:
    .quad .Lelan_var, 10, .Lelan_home
    .quad .Lhome_var, 5, .Luser_home
    .quad .Lrecursion_var, 21, .Lrecursion
    .quad 0
.Linstalled_prefix: .asciz "error: '"
.Linstalled_suffix: .asciz "' is already installed\n"
.Lquote_end: .asciz "'\n"
.Lnot_dir: .asciz "error: not a directory: '"
.Lnot_file: .asciz "error: not a file: '"
.Lcreate_home: .asciz "error: could not create home directory: '"
.Lcreate_toolchains: .asciz "error: could not create toolchains directory: '"
.Lcreate_link: .asciz "error: could not create link from '"
.Lto: .asciz "' to '"
.Lcollision: .asciz "error: could not remove 'install' directory: '"
.Lcause: .asciz "'\ninfo: caused by: "
.Los_error: .asciz " (os error "
.Lclose_paren: .asciz ")\n"
.Lrecursion_error: .asciz "error: infinite recursion detected\n"
.Lpath_error: .asciz "error: toolchain path exceeds 4095 bytes\n"
.Lhome_error: .asciz "error: could not resolve Elan home directory\n"
.Lutf8_error: .asciz "error: command arguments must be UTF-8\n"
.Lusage_text: .asciz "usage: elan toolchain list | elan toolchain link [--] NAME PATH\n"
.Lnot_found: .asciz "No such file or directory"
.Lpermission: .asciz "Permission denied"
.Lexists: .asciz "File exists"
.Lnot_directory: .asciz "Not a directory"
.Lreadonly: .asciz "Read-only file system"
.Lfull: .asciz "No space left on device"
.Llong: .asciz "Filename too long"
.Lloop: .asciz "Too many levels of symbolic links"
.Lother: .asciz "Filesystem error"
.balign 8
.Lerrors:
    .quad 2,.Lnot_found, 13,.Lpermission, 17,.Lexists, 20,.Lnot_directory
    .quad 28,.Lfull, 30,.Lreadonly, 36,.Llong, 40,.Lloop, 0,.Lother
.section .bss
.balign 8
.Lname_arg: .skip 8
.Lroot_arg: .skip 8
.Lelan_home: .skip 8
.Luser_home: .skip 8
.Lrecursion: .skip 8
.Lstat: .skip 144
.Lnumber: .skip 17
.Lhome: .skip CAP
.Lprobe: .skip CAP
.Ltarget: .skip CAP
.Ldestination: .skip CAP
.section .note.GNU-stack,"",@progbits
