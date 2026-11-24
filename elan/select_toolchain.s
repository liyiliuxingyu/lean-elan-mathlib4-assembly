/* SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Installed-toolchain portion of Elan 4.2.4's proxy_mode, config and toolchain.
 * Single-shot Linux x86-64 process. Buffers remain live through execve.
 */
.intel_syntax noprefix

.equ PATH_CAP, 4096
.equ FILE_CAP, 65536
.equ SYS_READ, 0
.equ SYS_WRITE, 1
.equ SYS_OPEN, 2
.equ SYS_CLOSE, 3
.equ SYS_STAT, 4
.equ SYS_FSTAT, 5
.equ SYS_LSTAT, 6
.equ SYS_GETCWD, 79
.equ REGULAR, 0x8000
.equ SYMLINK, 0xa000

.section .text
.globl elan_select_installed
.type elan_select_installed, @function
/* (explicit name or NULL, env name or NULL, absolute ELAN_HOME, notice suppression or NULL)
 * -> rax = selected descriptor, edx = kind. On error rax = 0 and
 * (rsi, rdx) is a diagnostic byte span suitable for write(2).
 */
.globl elan_select_for_command
elan_select_for_command:
    mov     byte ptr [rip+.Lmanager], 1
    mov     ecx, 1                  /* manager never emits the proxy override notice */
elan_select_installed:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rdx
    mov     [rip+.Lquiet], rcx
    lea     r14, [rip+.Ldot]        /* base for explicit, env, default inputs */
    test    r12, r12
    jnz     .Llookup
    mov     r12, rsi
    test    r12, r12
    jz      .Lsettings
    cmp     byte ptr [r12], 0
    je      .Lsettings
    mov     rdi, r12
    call    elan_strlen
    mov     rsi, rax
    mov     rdi, r12
    call    .Lutf8_ok               /* Rust env::var ignores non-Unicode env values */
    test    eax, eax
    jnz     .Llookup_valid

.Lsettings:
    mov     rsi, r13
    lea     r8, [rip+.Lsettings_file]
    call    .Lscratch_path
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    lea     rsi, [rip+.Lsettings_text]
    call    .Lread_regular
    xor     r15d, r15d              /* default if one exists */
    test    eax, eax
    js      .Lsettings_error
    jnz     .Lparse_settings
    mov     byte ptr [rip+elan_selection_missing_settings], 1
    jmp     .Ltoolchains_identity
.Lparse_settings:
    lea     rdi, [rip+.Lsettings_text]
    call    elan_settings_default
    cmp     rax, -1
    je      .Lsettings_error
    mov     r15, rax
.Ltoolchains_identity:
    /* stat follows symlinks in ELAN_HOME/toolchains, as does canonicalize_path. */
    mov     rsi, r13
    lea     r8, [rip+.Ltoolchains]
    call    .Lscratch_path
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    lea     rsi, [rip+.Lstat_buffer]
    mov     eax, SYS_STAT
    syscall
    test    rax, rax
    js      .Lcurrent_directory
    mov     rax, [rsi]             /* Linux x86-64 st_dev, st_ino */
    mov     [rip+.Ltc_dev], rax
    mov     rax, [rsi+8]
    mov     [rip+.Ltc_ino], rax
    mov     byte ptr [rip+.Ltc_present], 1
.Lcurrent_directory:
    lea     r14, [rip+.Ldirectory]
    mov     rdi, r14
    mov     esi, PATH_CAP
    mov     eax, SYS_GETCWD
    syscall
    test    rax, rax
    js      .Ldirectory_error
    lea     rbx, [r14+rax-1]        /* end of current absolute directory */
.Lancestor:
    mov     rcx, [rip+elan_override_count]
    lea     r8, [rip+elan_override_entries]
.Loverride:
    test    rcx, rcx
    jz      .Ltry_project
    mov     rdi, r14
    mov     rsi, [r8]
    call    .Lequal
    test    eax, eax
    jnz     .Lfrom_override
    add     r8, 16
    dec     rcx
    jmp     .Loverride
.Ltry_project:
    mov     rsi, r14
    lea     r8, [rip+.Lproject_file]
    call    .Lscratch_path
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    lea     rsi, [rip+.Lproject_text]
    call    .Lread_regular
    test    eax, eax
    js      .Lproject_error
    jnz     .Lproject
    mov     rsi, r14
    lea     r8, [rip+.Lleanpkg_file]
    call    .Lscratch_path
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    lea     rsi, [rip+.Lproject_text]
    call    .Lread_regular
    test    eax, eax
    js      .Lleanpkg_error
    jz      .Ltry_installation
    lea     rdi, [rip+.Lproject_text]
    call    elan_leanpkg_version
    cmp     rax, -1
    je      .Lleanpkg_error
    test    rax, rax
    jz      .Ltry_installation
    mov     r12, rax
    /* v4.2.4 passes no base_dir for legacy [package].lean_version. */
    lea     r14, [rip+.Ldot]
    jmp     .Llookup_valid
.Ltry_installation:
    cmp     byte ptr [rip+.Lmanager], 0
    je      .Lcheck_parent
    cmp     byte ptr [rip+.Ltc_present], 0
    jne     .Lcheck_parent
    /* Cfg::find_override_from_dir_walk canonicalizes the toolchains dir on
     * every ascent, including the last one when the current dir is "/". */
    mov     rsi, r13
    lea     r8, [rip+.Ltoolchains]
    call    .Lscratch_path
    jc      .Llength_error
    lea     r8, [rip+.Lscratch]
    push    r12
    mov     r12, r8
    call    .Lcanonical_notice
    pop     r12
.Lcheck_parent:
    lea     rax, [r14+1]
    cmp     rbx, rax
    je      .Ldefault
    /* Before visiting the parent, determine whether d is itself a direct
     * child of the installation directory. Prefer any project file at d.
     */
    cmp     byte ptr [rip+.Ltc_present], 0
    je      .Lparent
    mov     rsi, r14
    lea     r8, [rip+.Ldotdot]
    call    .Lscratch_path
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    lea     rsi, [rip+.Lstat_buffer]
    mov     eax, SYS_STAT
    syscall
    test    rax, rax
    js      .Lparent
    mov     rax, [rsi]
    cmp     rax, [rip+.Ltc_dev]
    jne     .Lparent
    mov     rax, [rsi+8]
    cmp     rax, [rip+.Ltc_ino]
    je      .Linside_toolchain
.Lparent:
    dec     rbx
    cmp     byte ptr [rbx], '/'
    jne     .Lparent
    cmp     rbx, r14
    jne     .Lshorten
    inc     rbx                    /* retain the leading slash at root */
.Lshorten:
    mov     byte ptr [rbx], 0
    jmp     .Lancestor
.Lfrom_override:
    mov     r12, [r8+8]             /* settings contain fully resolved descriptors */
    cmp     qword ptr [rip+.Lquiet], 0
    jne     .Lresolved
    call    .Loverride_notice
    jmp     .Lresolved
.Linside_toolchain:
    mov     rdi, rbx               /* basename of the installation directory */
.Lbasename:
    dec     rdi
    cmp     byte ptr [rdi], '/'
    jne     .Lbasename
    inc     rdi
    mov     rsi, rbx
    sub     rsi, rdi
    lea     r12, [rip+.Lscratch]
    mov     rdx, r12
    mov     ecx, PATH_CAP-1
    call    elan_decode_toolchain_dir
    test    rax, rax
    js      .Llength_error
    mov     byte ptr [r12+rax], 0
.Lresolved:
    mov     rdi, r12
    call    elan_strlen
    mov     rsi, rax
    mov     rdi, r12
    lea     rdx, [rip+.Lparsed]
    call    elan_parse_resolved
    test    eax, eax
    jz      .Lname_error
    mov     edx, eax
    mov     rax, r12
    jmp     .Lreturn
.Lproject:
    mov     [rip+elan_selection_project_root], r14
    lea     rdi, [rip+.Lproject_text]
    call    .Lfirst_line
    mov     r12, rax
    test    r12, r12
    jz      .Lproject_error
    jmp     .Llookup_valid
.Ldefault:
    test    r15, r15
    jz      .Lmissing_error
    mov     byte ptr [rip+elan_selection_from_default], 1
    mov     r12, r15
    lea     r14, [rip+.Ldot]
    jmp     .Llookup_valid

.Llookup:
    mov     rdi, r12
    call    elan_strlen
    mov     rsi, rax
    mov     rdi, r12
    call    .Lutf8_ok
    test    eax, eax
    jz      .Lname_error
.Llookup_valid:
    cmp     byte ptr [r12], 0
    je      .Lname_error
    /* As upstream, a directory containing bin/lean wins even for a bare name.
     * For project files the base is the file's own absolute parent directory.
     * For other sources upstream uses "." and preserves the lexical spelling.
     */
    lea     rdi, [rip+.Lscratch]
    lea     rdx, [rip+.Lscratch+PATH_CAP]
    mov     rsi, r12
    cmp     byte ptr [rsi], '/'
    je      .Labsolute
    mov     rsi, r14
    call    elan_append_z
    jc      .Llength_error
    mov     rsi, r12
    call    elan_join_component
    jmp     .Lprobe_root
.Labsolute:
    call    elan_append_z
.Lprobe_root:
    jc      .Llength_error
    mov     rbx, rdi
    lea     rsi, [rip+.Lbin_lean]
    call    elan_join_component
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    mov     eax, SYS_STAT
    mov     edx, REGULAR
    call    .Lis_type
    test    eax, eax
    jz      .Lparse_named
    mov     byte ptr [rbx], 0
    lea     rax, [rip+.Lscratch]
    mov     edx, 3
    jmp     .Lreturn
.Lparse_named:
    cmp     byte ptr [r12], '/'
    je      .Lpath_error
    cmp     byte ptr [r12], '.'
    jne     .Lparse_release
    lea     rsi, [r12+1]
    cmp     byte ptr [rsi], '.'
    jne     .Lpath_separator
    inc     rsi
.Lpath_separator:
    cmp     byte ptr [rsi], '/'
    je      .Lpath_error
    cmp     byte ptr [rsi], 92       /* backslash */
    je      .Lpath_error
.Lparse_release:
    mov     rdi, r12
    call    elan_strlen
    mov     rsi, rax
    mov     rdi, r12
    lea     rdx, [rip+.Lparsed]
    call    elan_parse_resolved
    test    eax, eax
    jz      .Lname_error
    mov     r15, [rip+.Lparsed+8]
    cmp     eax, 2
    jne     .Lcheck_link
    mov     r15, [rip+.Lparsed+24]  /* linked release overrides even an explicit origin */
.Lcheck_link:
    mov     rsi, r13
    lea     r8, [rip+.Ltoolchains]
    call    .Lscratch_path
    jc      .Llength_error
    mov     rsi, r15
    call    elan_join_component
    jc      .Llength_error
    lea     rdi, [rip+.Lscratch]
    mov     eax, SYS_LSTAT
    mov     edx, SYMLINK
    call    .Lis_type
    test    eax, eax
    jz      .Lremote
    mov     rax, r15
    mov     edx, 1
    jmp     .Lreturn
.Lremote:
    /* Floating channels require upstream release metadata. */
    lea     rbx, [rip+.Lchannels]
.Lchannel:
    mov     rsi, [rbx]
    test    rsi, rsi
    jz      .Lorigin
    mov     rdi, r15
    call    .Lequal
    test    eax, eax
    jnz     .Lchannel_error
    add     rbx, 8
    jmp     .Lchannel
.Lorigin:
    lea     rsi, [rip+.Ldefault_origin]
    mov     ecx, OFFSET FLAT:.Ldefault_origin_len
    cmp     dword ptr [rip+.Lparsed], 2
    jne     .Lcopy_origin
    mov     rsi, [rip+.Lparsed+8]
    mov     rcx, [rip+.Lparsed+16]
.Lcopy_origin:
    /* Reserve the origin's NUL. Each subsequent append checks its own bound. */
    cmp     rcx, PATH_CAP-1
    ja      .Llength_error
    mov     rbx, rcx
    lea     rdi, [rip+.Lscratch]
    rep movsb
    mov     byte ptr [rdi], 0
    lea     rdx, [rip+.Lscratch+PATH_CAP]
    mov     r8, rdi
    mov     rsi, r15
    lea     rdi, [rip+.Lnightly_word]
    mov     ecx, 7
    repe cmpsb                     /* stops at NUL on short input */
    mov     rdi, r8
    jne     .Lcolon
    cmp     rbx, 8
    jb      .Ladd_nightly
    lea     rsi, [rdi-8]
    lea     rdi, [rip+.Lnightly_suffix]
    mov     ecx, 8
    repe cmpsb
    mov     rdi, r8
    je      .Lcolon
.Ladd_nightly:
    lea     rsi, [rip+.Lnightly_suffix]
    call    elan_append_z
    jc      .Llength_error
.Lcolon:
    lea     rsi, [rip+.Lcolon_text]
    call    elan_append_z
    jc      .Llength_error
    movzx   eax, byte ptr [r15]
    sub     eax, '0'
    cmp     eax, 9
    ja      .Lrelease
    lea     rsi, [rip+.Lv]
    call    elan_append_z
    jc      .Llength_error
.Lrelease:
    mov     rsi, r15
    call    elan_append_z
    jc      .Llength_error
    lea     rax, [rip+.Lscratch]
    mov     edx, 2
    jmp     .Lreturn

.macro ERROR label, message, status=0
\label:
    mov     ecx, \status
    lea     rsi, [rip+\message]
    mov     edx, OFFSET FLAT:\message\()_len
    xor     eax, eax
    jmp     .Lreturn
.endm
ERROR .Llength_error, .Ltoo_long
ERROR .Lsettings_error, .Lbad_settings
ERROR .Lproject_error, .Lbad_project
ERROR .Lleanpkg_error, .Lbad_leanpkg
ERROR .Ldirectory_error, .Lbad_directory
ERROR .Lmissing_error, .Lmissing, 3
.Lname_error:
    mov     r8, r12
    jmp     .Linvalid_name
ERROR .Linvalid_name, .Lbad_name, 1
.Lpath_error:
    /* Retain both strings for the manager's detailed path diagnostic. */
    lea     rsi, [rip+.Lscratch]
    lea     rdi, [rip+.Lproject_text]
    lea     rdx, [rip+.Lproject_text+PATH_CAP]
    call    elan_append_z
    mov     byte ptr [rbx], 0
    lea     r8, [rip+.Lscratch]
    lea     r9, [rip+.Lproject_text]
ERROR .Linvalid_path, .Lbad_path, 2
ERROR .Lchannel_error, .Lfloating
.Lreturn:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.size elan_select_installed, .-elan_select_installed

/* Assemble root rsi and component r8 in Lscratch, preserving append conventions. */
.Lscratch_path:
    lea     rdi, [rip+.Lscratch]
    lea     rdx, [rip+.Lscratch+PATH_CAP]
    sub     rsp, 8
    call    elan_append_z
    lea     rsp, [rsp+8]
    jc      .Lscratch_full
    mov     rsi, r8
    jmp     elan_join_component
.Lscratch_full:
    ret

/* Write the standard two-line database override notice. r12 = name, r14 =
 * canonical directory. A suppressed notice never enters this routine.
 */
.Lcanonical_notice:
    push    rbx
    lea     rbx, [rip+.Lwarn_sequence]
    jmp     .Lnotice_piece
.Loverride_notice:
    push    rbx
    lea     rbx, [rip+.Lnotice_sequence]
.Lnotice_piece:
    mov     rdi, [rbx]
    test    rdi, rdi
    jz      .Lnotice_end
    cmp     rdi, 1
    cmove   rdi, r12
    cmp     rdi, 2
    cmove   rdi, r14
    mov     rsi, rdi
    call    elan_strlen
    mov     rdx, rax
.Lnotice_write:
    test    rdx, rdx
    jz      .Lnotice_next
    mov     edi, 2
    mov     eax, SYS_WRITE
    syscall
    cmp     rax, -4
    je      .Lnotice_write
    test    rax, rax
    jle     .Lnotice_end
    add     rsi, rax
    sub     rdx, rax
    jmp     .Lnotice_write
.Lnotice_next:
    add     rbx, 8
    jmp     .Lnotice_piece
.Lnotice_end:
    pop     rbx
    ret

/* (rdi, rsi) -> byte strings are equal. */
.Lequal:
    lodsb
    cmp     [rdi], al
    jne     .Ldifferent
    inc     rdi
    test    al, al
    jnz     .Lequal
    mov     eax, 1
    ret
.Ldifferent:
    xor     eax, eax
    ret

/* eax = stat/lstat, rdi = path, edx = S_IFMT value. */
.Lis_type:
    lea     rsi, [rip+.Lstat_buffer]
    syscall
    test    rax, rax
    js      .Ldifferent
    movzx   eax, word ptr [rsi+24]  /* Linux x86-64 struct stat.st_mode */
    and     eax, 0xf000
    cmp     eax, edx
    sete    al
    movzx   eax, al
    ret

/* (rdi=bytes, rsi=count). Reuse the project's scalar UTF-8 validator. */
.Lutf8_ok:
    sub     rsp, 24
    mov     qword ptr [rsp], 0
    mov     qword ptr [rsp+8], 0
    mov     rdx, rsp
    lea     rcx, [rsp+8]
    call    _ZN4lean13validate_utf8EPKhmRmS2_
    add     rsp, 24
    ret

/* (pathname, FILE_CAP+1 bytes of storage) -> 1 present, 0 absent/nonregular,
 * -1 error. Reject embedded NUL and malformed UTF-8 throughout the file.
 * O_NONBLOCK and a second type check handle a file replaced during open.
 */
.Lread_regular:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
    lea     rsi, [rip+.Lstat_buffer]
    mov     eax, SYS_STAT
    syscall
    cmp     rax, -2                 /* ENOENT or ENOTDIR */
    je      .Lfile_absent
    cmp     rax, -20
    je      .Lfile_absent
    test    rax, rax
    js      .Lfile_error
    movzx   eax, word ptr [rsi+24]
    and     eax, 0xf000
    cmp     eax, REGULAR
    jne     .Lfile_absent
.Lopen:
    mov     rdi, r12
    mov     esi, 0x80800            /* O_CLOEXEC | O_NONBLOCK | O_RDONLY */
    mov     eax, SYS_OPEN
    syscall
    cmp     rax, -4
    je      .Lopen
    test    rax, rax
    js      .Lfile_error
    mov     r14, rax
    mov     rdi, r14
    lea     rsi, [rip+.Lstat_buffer]
    mov     eax, SYS_FSTAT
    syscall
    test    rax, rax
    js      .Lclose_error
    movzx   eax, word ptr [rsi+24]
    and     eax, 0xf000
    cmp     eax, REGULAR
    jne     .Lclose_error
    xor     ebx, ebx
.Lread_more:
    mov     rdi, r14
    lea     rsi, [r13+rbx]
    mov     edx, FILE_CAP+1
    sub     rdx, rbx
    mov     ecx, 4096
    cmp     rdx, rcx
    cmova   rdx, rcx               /* bounded chunks, with a final overflow probe */
    mov     eax, SYS_READ
    syscall
    cmp     rax, -4
    je      .Lread_more
    test    rax, rax
    js      .Lclose_error
    jz      .Lread_end
    add     rbx, rax
    cmp     rbx, FILE_CAP
    jbe     .Lread_more
.Lclose_error:
    mov     r15d, -1
    jmp     .Lclose
.Lread_end:
    mov     byte ptr [r13+rbx], 0
    xor     eax, eax
    mov     rdi, r13
    mov     rcx, rbx
    test    rcx, rcx
    jz      .Lcheck_file_utf8
    repne scasb
    je      .Lclose_error
.Lcheck_file_utf8:
    mov     rdi, r13
    mov     rsi, rbx
    call    .Lutf8_ok
    test    eax, eax
    jz      .Lclose_error
    mov     r15d, 1
.Lclose:
    mov     rdi, r14
    mov     eax, SYS_CLOSE
    syscall
    mov     eax, r15d
    jmp     .Lfile_return
.Lfile_error:
    mov     eax, -1
    jmp     .Lfile_return
.Lfile_absent:
    xor     eax, eax
.Lfile_return:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

/* Rust str::lines().next() and Unicode str::trim() on a validated text file.
 * Track first and last non-whitespace scalar while preserving interior bytes.
 */
.Lfirst_line:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    mov     r12, rdi
    call    elan_strlen
    mov     r13, rax
    xor     r14d, r14d
    mov     qword ptr [rsp], 0
.Lscalar:
    mov     rbx, [rsp]
    cmp     rbx, r13
    jae     .Ltrim_end
    cmp     byte ptr [r12+rbx], 10
    je      .Ltrim_end
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, rsp
    call    _ZN4lean9next_utf8EPKcmRm
    cmp     eax, 0x20
    je      .Lscalar
    lea     ecx, [rax-9]
    cmp     ecx, 4
    jbe     .Lscalar
    cmp     eax, 0x85
    je      .Lscalar
    cmp     eax, 0xa0
    je      .Lscalar
    cmp     eax, 0x1680
    je      .Lscalar
    lea     ecx, [rax-0x2000]
    cmp     ecx, 10
    jbe     .Lscalar
    lea     ecx, [rax-0x2028]
    cmp     ecx, 1
    jbe     .Lscalar
    cmp     eax, 0x202f
    je      .Lscalar
    cmp     eax, 0x205f
    je      .Lscalar
    cmp     eax, 0x3000
    je      .Lscalar
    lea     rax, [r12+rbx]
    test    r14, r14
    cmovz   r14, rax
    mov     r15, [rsp]
    jmp     .Lscalar
.Ltrim_end:
    test    r14, r14
    jz      .Ltrim_return
    mov     byte ptr [r12+r15], 0
.Ltrim_return:
    mov     rax, r14
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

.section .rodata
.Ldot:             .asciz "."
.Ldotdot:          .asciz ".."
.Ltoolchains:      .asciz "toolchains"
.Lproject_file:    .asciz "lean-toolchain"
.Lleanpkg_file:    .asciz "leanpkg.toml"
.Lsettings_file:   .asciz "settings.toml"
.Lbin_lean:        .asciz "bin/lean"
.Ldefault_origin:  .asciz "leanprover/lean4"
.equ .Ldefault_origin_len, .-.Ldefault_origin-1
.Lcolon_text:      .asciz ":"
.Lv:               .asciz "v"
.Lnightly_suffix:  .ascii "-"
.Lnightly_word:    .asciz "nightly"
.Lstable:          .asciz "stable"
.Lbeta:            .asciz "beta"
.balign 8
.Lchannels:        .quad .Lstable, .Lbeta, .Lnightly_word, .Lproject_file, 0
.Lnotice_tool:     .asciz "note: using toolchain '"
.Lnotice_from:     .asciz "' from override set on '"
.Lnotice_remove:   .asciz "'\nnote: to remove: elan override unset --path '"
.Lnotice_suppress: .asciz "' | to suppress: ELAN_NO_OVERRIDE_NOTICE=1\n"
.balign 8
.Lwarn_sequence: .quad .Lwarn_prefix, 1, .Lwarn_end, 0
.Lnotice_sequence: .quad .Lnotice_tool, 1, .Lnotice_from, 2, .Lnotice_remove, 2, .Lnotice_suppress, 0

.Lwarn_prefix: .asciz "warning: could not canonicalize path: '"
.Lwarn_end: .asciz "'\n"

.macro MESSAGE label, value
\label: .ascii "elan-asm-proxy: \value\n"
.equ \label\()_len, .-\label
.endm
MESSAGE .Ltoo_long, "toolchain or filesystem path exceeds 4095 bytes"
MESSAGE .Lbad_settings, "invalid, unreadable or unsupported settings.toml"
MESSAGE .Lbad_leanpkg, "invalid, unreadable or unsupported leanpkg.toml"
MESSAGE .Lbad_project, "invalid or unreadable lean-toolchain file"
MESSAGE .Lbad_directory, "cannot determine the current directory"
MESSAGE .Lmissing, "no toolchain selected by argument, environment, project or default"
MESSAGE .Lbad_name, "invalid toolchain name or relative toolchain path"
MESSAGE .Lbad_path, "toolchain path must contain a regular bin/lean"
MESSAGE .Lfloating, "floating channel requires release metadata; specify a pinned release or linked toolchain"

.section .bss
.balign 8
.Lquiet:           .skip 8
.Ltc_dev:          .skip 8
.Ltc_ino:          .skip 8
.Lparsed:          .skip 40
.Lstat_buffer:     .skip 144
.Ldirectory:       .skip PATH_CAP
.Lscratch:         .skip PATH_CAP
.Lsettings_text:   .skip FILE_CAP+1
.Lproject_text:    .skip FILE_CAP+1
.Lmanager:         .skip 1
.Ltc_present:      .skip 1
.globl elan_selection_from_default
elan_selection_from_default: .skip 1
.globl elan_selection_missing_settings, elan_selection_project_root
elan_selection_missing_settings: .skip 1
.balign 8
elan_selection_project_root: .skip 8

.section .note.GNU-stack,"",@progbits
