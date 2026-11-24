# SPDX-License-Identifier: Apache-2.0
# Demand-driven breadth-first lookup over Lean 4.19.0 cache imports.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ SYS_close,          3
.equ SYS_fstat,          5
.equ SYS_mmap,           9
.equ SYS_munmap,        11
.equ SYS_openat,       257
.equ AT_FDCWD,        -100
.equ O_NONBLOCK,      0x800
.equ O_CLOEXEC,     0x80000
.equ PROT_READ,          1
.equ PROT_WRITE,         2
.equ MAP_PRIVATE,        2
.equ MAP_ANONYMOUS,   0x20
.equ EINTR,             -4
.equ ENOMEM,           -12
.equ S_IFMT,       0xf000
.equ S_IFREG,      0x8000
.equ PATH_BYTES,      4096
.equ MAX_MODULES,    65536
.equ TABLE_SLOTS,    2 * MAX_MODULES
.equ NAME_ARENA_BYTES, 16 * 1024 * 1024

# Work mapping: book-keeping, one module view, I/O buffers, and a queue.
.equ G_SEARCH_PATH,       0
.equ G_ARGC,              8
.equ G_ARGV,             16
.equ G_ANSWERS,          24
.equ G_REMAINING,        32
.equ G_READ_INDEX,       40
.equ G_QUEUED,           48
.equ G_NAME_BYTES,       56
.equ G_MAPPING,          64
.equ G_MAPPING_SIZE,     72
.equ G_ROOT_SEEN,        80
.equ G_ROOT_DEV,         88
.equ G_ROOT_INO,         96
.equ G_ACTIVE_PATH,     104
.equ G_ERROR_BUFFER,    112
.equ G_VIEW,            120
.equ G_RESULT,          G_VIEW + VIEW_BYTES
.equ G_STAT,            G_RESULT + RESULT_BYTES
.equ G_RESOLVER,        G_STAT + 144
.equ G_IMPORT_PATH,     G_RESOLVER + 64
.equ G_FILE_PATH,       G_IMPORT_PATH + PATH_BYTES
.equ G_QUEUE,           G_FILE_PATH + PATH_BYTES
.equ G_TABLE,           G_QUEUE + MAX_MODULES * 8
.equ G_ARENA,           G_TABLE + TABLE_SLOTS * 16
.equ G_WORK_BYTES,      G_ARENA + NAME_ARENA_BYTES

.section .text
.globl mathlib_olean_search_graph
.type mathlib_olean_search_graph,@function
# SysV: rdi = root file, rsi = LEAN_PATH or NULL, rdx = argc (>0), rcx = argv,
# r8 = argc writable answer bytes, r9 = optional 4096-byte error-path buffer.
# eax: 0 = complete or exhausted, -1 = invalid query, -2 = incompatible image,
#      -3 = cannot locate/read a module, -4 = work memory/path limit.
# On 0, each answer is ConstantInfo tag + 1, or 0 for a missing name.
mathlib_olean_search_graph:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r13, rdi
    mov r14, rsi
    mov r15, rdx
    mov rbp, rcx
    mov rbx, r8
    mov [rsp], r9
    test r9, r9
    jz .Largs
    mov byte ptr [r9], 0
.Largs:
    test r15, r15
    jz .Lno_queries
    xor edi, edi
    mov esi, G_WORK_BYTES
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8d, -1
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    cmp rax, -4095
    jae .Lno_workspace
    mov r12, rax
    mov [r12 + G_SEARCH_PATH], r14
    mov [r12 + G_ARGC], r15
    mov [r12 + G_REMAINING], r15
    mov [r12 + G_ARGV], rbp
    mov [r12 + G_ANSWERS], rbx
    mov rax, [rsp]
    mov [r12 + G_ERROR_BUFFER], rax
    mov rdi, rbx
    mov rcx, r15
    xor eax, eax
    rep stosb
    mov rdi, r13
    call .Lmap_file
    test eax, eax
    js .Lfinish

.Lsearch_module:
    xor ebx, ebx
.Lquery:
    cmp rbx, [r12 + G_ARGC]
    jae .Lmodule_imports
    mov r8, [r12 + G_ANSWERS]
    cmp byte ptr [r8 + rbx], 0
    jne .Lnext_query

    lea rdi, [r12 + G_VIEW]
    mov rsi, [r12 + G_ARGV]
    mov rsi, [rsi + rbx * 8]
    lea rdx, [r12 + G_RESULT]
    call mathlib_olean_lookup
    test eax, eax
    js .Lfinish
    jz .Lnext_query
    mov eax, [r12 + G_RESULT + RESULT_KIND]
    inc eax
    mov r8, [r12 + G_ANSWERS]
    mov [r8 + rbx], al
    dec qword ptr [r12 + G_REMAINING]
    jz .Lsuccess
.Lnext_query:
    inc rbx
    jmp .Lquery

.Lmodule_imports:
    xor r13d, r13d
.Limport:
    cmp r13, [r12 + G_VIEW + VIEW_IMPORTS]
    jae .Lrelease_module
    lea rdi, [r12 + G_VIEW]
    mov rsi, r13
    lea rdx, [r12 + G_IMPORT_PATH]
    mov ecx, PATH_BYTES
    call mathlib_olean_import_path
    cmp eax, -3                      # runtime-only import
    je .Lnext_import
    cmp eax, -2
    je .Lfinish
    test eax, eax
    js .Lworkspace_error
    lea rdi, [r12 + G_IMPORT_PATH]
    mov esi, eax
    call .Lenqueue
    test eax, eax
    js .Lfinish
.Lnext_import:
    inc r13
    jmp .Limport

.Lrelease_module:
    call .Lunmap_file
.Lnext_module:
    mov rax, [r12 + G_READ_INDEX]
    cmp rax, [r12 + G_QUEUED]
    jae .Lsuccess
    lea rcx, [rax + 1]
    mov [r12 + G_READ_INDEX], rcx
    mov r14, [r12 + G_QUEUE + rax * 8]
    mov [r12 + G_ACTIVE_PATH], r14

    mov rdi, [r12 + G_SEARCH_PATH]
    mov rsi, r14
    lea rdx, [r12 + G_FILE_PATH]
    lea rcx, [r12 + G_RESOLVER]
    call mathlib_olean_resolve
    test eax, eax
    js .Lworkspace_error
    jz .Lread_error
    lea rdi, [r12 + G_FILE_PATH]
    call .Lmap_file
    test eax, eax
    js .Lfinish
    jnz .Lnext_module               # the explicit root reached via its name
    jmp .Lsearch_module

.Lworkspace_error:
    mov eax, -4
    jmp .Lfinish
.Lread_error:
    mov eax, -3
    jmp .Lfinish
.Lsuccess:
    xor eax, eax
.Lfinish:
    mov ebx, eax
    cmp ebx, -3
    jne .Lcleanup
    mov rdi, [r12 + G_ERROR_BUFFER]
    test rdi, rdi
    jz .Lcleanup
    mov rsi, [r12 + G_ACTIVE_PATH]
    mov ecx, PATH_BYTES - 1
.Lcopy_error:
    lodsb
    stosb
    test al, al
    jz .Lcleanup
    dec ecx
    jnz .Lcopy_error
    mov byte ptr [rdi], 0
.Lcleanup:
    call .Lunmap_file
    mov rdi, r12
    mov esi, G_WORK_BYTES
    mov eax, SYS_munmap
    syscall
    mov eax, ebx
    jmp .Lreturn

.Lno_queries:
    mov eax, -1
    jmp .Lreturn
.Lno_workspace:
    mov eax, -4
.Lreturn:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size mathlib_olean_search_graph, .-mathlib_olean_search_graph

# Map a module, record the root's identity, and initialize the shared view.
# 1 means an import aliases the already visited explicit root.
.type .Lmap_file,@function
.Lmap_file:
    push rbx
    mov [r12 + G_ACTIVE_PATH], rdi
    mov rsi, rdi
    mov edi, AT_FDCWD
    mov edx, O_NONBLOCK | O_CLOEXEC
    xor r10d, r10d
.Lopen_file:
    mov eax, SYS_openat
    syscall
    cmp rax, EINTR
    je .Lopen_file
    test rax, rax
    js .Lfile_read_error
    mov ebx, eax
    mov edi, ebx
    lea rsi, [r12 + G_STAT]
.Lstat_file:
    mov eax, SYS_fstat
    syscall
    cmp rax, EINTR
    je .Lstat_file
    test rax, rax
    js .Lbad_descriptor
    mov eax, [rsi + 24]             # stat.st_mode
    and eax, S_IFMT
    cmp eax, S_IFREG
    jne .Lbad_descriptor
    mov rdx, [rsi]                  # stat.st_dev
    mov rcx, [rsi + 8]              # stat.st_ino
    cmp qword ptr [r12 + G_ROOT_SEEN], 0
    je .Lremember_root
    cmp [r12 + G_ROOT_DEV], rdx
    jne .Lmap_regular
    cmp [r12 + G_ROOT_INO], rcx
    je .Lroot_alias
    jmp .Lmap_regular
.Lremember_root:
    mov qword ptr [r12 + G_ROOT_SEEN], 1
    mov [r12 + G_ROOT_DEV], rdx
    mov [r12 + G_ROOT_INO], rcx
.Lmap_regular:
    mov rsi, [rsi + 48]             # stat.st_size
    cmp rsi, 96
    jl .Lbad_size
    mov [r12 + G_MAPPING_SIZE], rsi
    xor edi, edi
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8d, ebx
    xor r9d, r9d
    mov eax, SYS_mmap
    syscall
    mov r8, rax
    jmp .Lclose_file
.Lbad_descriptor:
    mov r8, -3
    jmp .Lclose_file
.Lbad_size:
    mov r8, -2
    jmp .Lclose_file
.Lroot_alias:
    xor r8d, r8d
.Lclose_file:
    mov edi, ebx
    mov eax, SYS_close
    syscall
    test r8, r8
    jz .Lalias_return
    cmp r8, -4095
    jb .Lparse_file
    cmp r8, -2
    je .Limage_error
    cmp r8, ENOMEM
    je .Lmap_memory_error
.Lfile_read_error:
    mov eax, -3
    pop rbx
    ret
.Limage_error:
    mov eax, -2
    pop rbx
    ret
.Lmap_memory_error:
    mov eax, -4
    pop rbx
    ret
.Lalias_return:
    mov eax, 1
    pop rbx
    ret
.Lparse_file:
    mov [r12 + G_MAPPING], r8
    mov rdi, r8
    mov rsi, [r12 + G_MAPPING_SIZE]
    lea rdx, [r12 + G_VIEW]
    call mathlib_olean_parse
    test eax, eax
    jz .Limage_error
    xor eax, eax
    pop rbx
    ret
.size .Lmap_file, .-.Lmap_file

.Lunmap_file:
    mov rdi, [r12 + G_MAPPING]
    test rdi, rdi
    jz .Lunmap_done
    mov rsi, [r12 + G_MAPPING_SIZE]
    mov eax, SYS_munmap
    syscall
    mov qword ptr [r12 + G_MAPPING], 0
.Lunmap_done:
    ret

# Insert an imported file name only once. Queue entries and hash keys share
# the same NUL-terminated copy. rdi = name, esi = length (excluding NUL).
.Lenqueue:
    mov r8, rdi
    mov edx, esi
    movabs rax, 0xcbf29ce484222325   # FNV-1a, 64-bit
    movabs r9, 0x100000001b3
    lea rsi, [r8 + rdx]
    mov rcx, rdi
.Lhash_byte:
    cmp rcx, rsi
    jae .Lhash_ready
    movzx edi, byte ptr [rcx]
    xor rax, rdi
    imul rax, r9
    inc rcx
    jmp .Lhash_byte
.Lhash_ready:
    mov r9d, eax
.Lprobe_slot:
    and r9d, TABLE_SLOTS - 1
    mov ecx, r9d
    shl rcx, 4
    lea r10, [r12 + G_TABLE + rcx]
    mov rdi, [r10]
    test rdi, rdi
    jz .Lempty_slot
    cmp [r10 + 8], rax
    jne .Lprobe_next
    mov rsi, r8
    lea rcx, [rdx + 1]
    repe cmpsb
    je .Lenqueue_done
.Lprobe_next:
    inc r9d
    jmp .Lprobe_slot

.Lempty_slot:
    mov r9, [r12 + G_QUEUED]
    cmp r9, MAX_MODULES
    jae .Lenqueue_full
    mov rcx, [r12 + G_NAME_BYTES]
    lea rsi, [rcx + rdx + 1]
    cmp rsi, NAME_ARENA_BYTES
    ja .Lenqueue_full
    mov [r12 + G_NAME_BYTES], rsi
    lea rdi, [r12 + G_ARENA + rcx]
    mov [r10], rdi
    mov [r10 + 8], rax
    mov [r12 + G_QUEUE + r9 * 8], rdi
    inc r9
    mov [r12 + G_QUEUED], r9
    mov rsi, r8
    lea rcx, [rdx + 1]
    rep movsb
.Lenqueue_done:
    xor eax, eax
    ret
.Lenqueue_full:
    mov eax, -4
    ret

.section .note.GNU-stack,"",@progbits
