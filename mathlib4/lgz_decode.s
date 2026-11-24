# SPDX-License-Identifier: Apache-2.0
# leangz v0.1.15 compact object stream, Linux x86-64 System V.
.intel_syntax noprefix

# Each mapping descriptor has a base pointer followed by a byte capacity.
.equ OUTPUT,       0
.equ FRAMES,      16
.equ VALUES,      32
.equ REFERENCES,  48
.equ BASE,        64
.equ GMP,         72
.equ FIXUP,       80
.equ OUT_PARAM,   88
.equ LEN_PARAM,   96
.equ FRAME_BYTES,104
.equ VALUE_BYTES,112
.equ REF_BYTES,  120
.equ RESULT,     128
.equ NEXT_SIZE,  136
.equ DATA_LEN,   144
.equ AUX,        152
.equ SCALAR,     160
.equ CTX_SIZE,   168

# Continuation for a pending node; no traversal uses the machine stack.
.equ F_KIND,    0
.equ F_OPCODE,  1
.equ F_TAG,     2
.equ F_APPS,    3
.equ F_SCALARS, 4          # u16, number of u64 scalar words
.equ F_MODES,   6          # bit i selects exprish for the ith remaining child
.equ F_FIELDS,  8          # total count, u64 for arrays
.equ F_LEFT,   16
.equ F_START,  24          # byte index into VALUES
.equ F_SIZE,   32
.equ K_SAVE,    1
.equ K_CTOR,    2
.equ K_ARRAY,   3
.equ K_REF,     4
.equ K_EXPR,    5

# r12 input cursor, r13 input end, r14 output mapping, r15 output bytes used.
# rbx is the current continuation, rbp is the per-call context.
.macro input_need n
    mov rdx, r13
    sub rdx, r12
    cmp rdx, \n
    jb .Lfail
.endm

.text
.globl lgz_decode
.type lgz_decode,@function
# int lgz_decode(input, size, out_pointer, out_length)
# Caller owns the returned mmap and can munmap(pointer,length).
lgz_decode:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, CTX_SIZE
    mov rbp, rsp
    mov r12, rdi
    mov r13, rsi
    mov r8, rdx
    mov r9, rcx
    xor eax, eax
    mov rdi, rbp
    mov ecx, CTX_SIZE/8
    rep stosq
    test r8, r8
    jz .Lfail
    test r9, r9
    jz .Lfail
    mov [r8], rax
    mov [r9], rax
    mov [rbp+OUT_PARAM], r8
    mov [rbp+LEN_PARAM], r9
    test r12, r12
    jz .Lfail
    add r13, r12
    jc .Lfail
    input_need 16
    mov edx, [r12+4]
    shl rdx, 16
    mov [rbp+BASE], rdx
    mov byte ptr [rbp+GMP], 1         # Linux x86-64 default for LGZ! and LGZ1
    xor r15d, r15d
    # Use a plausible size hint for the first allocation. Larger streams can
    # still grow, and an arbitrary header cannot reserve an unbounded mapping.
    mov eax, [r12]
    and eax, 0xffffff
    cmp eax, 0x5a474c
    jne .Lfail
    mov rsi, [r12+8]
    cmp rsi, 4096
    jbe .Lcheck_magic
    mov rax, r13
    sub rax, r12
    shr rsi, 6
    cmp rsi, rax
    ja .Lcheck_magic
    mov rsi, [r12+8]
    mov eax, 4194304
    cmp rsi, rax
    cmova rsi, rax
    add rsi, 4095
    and rsi, -4096
    call .Lmap_anonymous
    cmp rax, -4095
    jae .Lcheck_magic                 # hint is optional
    mov r14, rax
    mov [rbp+OUTPUT], rax
    mov [rbp+OUTPUT+8], rsi
.Lcheck_magic:
    mov eax, [r12]
    add r12, 16
    cmp eax, 0x215a474c               # LGZ!
    je .Lversion0
    cmp eax, 0x315a474c
    je .Lversion1
    cmp eax, 0x325a474c
    jne .Lfail

    input_need 42
    mov eax, 96
    call .Lreserve
    mov dword ptr [rdi], 0x61656c6f   # olean
    mov word ptr [rdi+4], 0x026e
    movzx eax, byte ptr [r12+40]
    test al, 0xfe
    jnz .Lfail
    mov [rbp+GMP], rax
    mov [rdi+6], al
    lea rdi, [r14+40]
    mov rsi, r12
    mov ecx, 40
    rep movsb
    add r12, 41
    lea rdi, [r14+7]
    cmp byte ptr [r12], 0
    je .Lver_raw
    input_need 4
    movzx eax, byte ptr [r12]
    call .Ldecimal
    mov al, '.'
    stosb
    movzx eax, byte ptr [r12+1]
    call .Ldecimal
    mov al, '.'
    stosb
    movzx eax, byte ptr [r12+2]
    call .Ldecimal
    cmp byte ptr [r12+3], 255
    je .Lver_regular_end
    mov dword ptr [rdi], 0x0063722d
    add rdi, 3
    movzx eax, byte ptr [r12+3]
    inc eax
    call .Ldecimal
.Lver_regular_end:
    add r12, 4
    jmp .Lheader_end
.Lver_raw:
    inc r12
    input_need 33
    mov rsi, r12
    mov ecx, 33
    rep movsb
    add r12, 33
    jmp .Lheader_end
.Lversion1:
    input_need 40
    mov eax, 64
    call .Lreserve
    mov dword ptr [rdi], 0x61656c6f
    mov word ptr [rdi+4], 0x016e
    add rdi, 6
    mov rsi, r12
    mov ecx, 40
    rep movsb
    add r12, 40
    jmp .Lheader_end
.Lversion0:
    mov eax, 32
    call .Lreserve
    movabs rax, 0x6c69666e61656c6f
    mov [rdi], rax
    movabs rax, 0x2121212121212165
    mov [rdi+8], rax
.Lheader_end:
    mov rax, [rbp+BASE]
    mov [r14+r15-16], rax
    lea rax, [r15-8]
    mov [rbp+FIXUP], rax

.Lnormal:
    xor edi, edi
    jmp .Lread_tag
.Lexprish:
    mov edi, 1
.Lread_tag:
    cmp r12, r13
    jae .Lfail
    movzx eax, byte ptr [r12]
    inc r12
    cmp eax, 0xd0
    jb .Lmode_tag
    cmp eax, 0xf0
    jb .Limmediate
    cmp eax, 0xf8
    jb .Lref_inline
    cmp eax, 0xfc
    jb .Limmediate
    cmp eax, 0xff
    je .Lsave
    cmp eax, 0xfd
    je .Lref16
    ja .Lref32
    input_need 1
    movzx eax, byte ptr [r12]
    inc r12
    jmp .Llookup
.Lref16:
    input_need 2
    movzx eax, word ptr [r12]
    add r12, 2
    jmp .Llookup
.Lref32:
    input_need 4
    mov eax, [r12]
    add r12, 4
    jmp .Llookup
.Lref_inline:
    sub eax, 0xf0
.Llookup:
    shl rax, 3
    cmp rax, [rbp+REF_BYTES]
    jae .Lfail
    mov rdx, [rbp+REFERENCES]
    mov rax, [rdx+rax]
    jmp .Ldone_value
.Limmediate:
    call .Lint_tag
    lea rax, [rax*2+1]
    jmp .Ldone_value
.Lsave:
    mov [rbp+AUX], edi
    call .Lnewframe
    mov byte ptr [rbx+F_KIND], K_SAVE
    mov edi, [rbp+AUX]
    jmp .Lread_tag

.Lmode_tag:
    test edi, edi
    jnz .Lexpr_tag
    test al, 15
    jnz .Lsmall_ctor
    cmp al, 0x00
    je .Larray
    cmp al, 0x10
    je .Lbig_ctor
    cmp al, 0x20
    je .Lscalar_array
    cmp al, 0x30
    je .Lstring
    cmp al, 0x40
    je .Lmpz
    cmp al, 0x80
    je .Lexprish
    cmp al, 0x90
    jbe .Lruntime_ref
.Lsmall_ctor:
    call .Lnewframe
    mov edx, eax
    shr edx, 4
    mov [rbx+F_TAG], dl
    and eax, 15
    mov edx, eax
    and edx, 1
    mov [rbx+F_SCALARS], dx
    shr eax, 1
    jmp .Lctor_fields
.Lbig_ctor:
    input_need 4
    call .Lnewframe
    movzx eax, byte ptr [r12]
    cmp eax, 244                     # upper tags belong to runtime objects
    jae .Lfail
    mov [rbx+F_TAG], al
    movzx edx, word ptr [r12+2]
    mov [rbx+F_SCALARS], dx
    movzx eax, byte ptr [r12+1]
    add r12, 4
    lea edx, [rdx+rax+1]
    cmp edx, 8191                    # .olean ctor byte size must fit u16
    ja .Lfail
.Lctor_fields:
    mov byte ptr [rbx+F_KIND], K_CTOR
    jmp .Lbegin_fields
.Larray:
    call .Lnewframe
    call .Lread_int
    test rax, rax
    js .Lfail
    input_need rax                    # each child needs at least one opcode
    mov byte ptr [rbx+F_KIND], K_ARRAY
    jmp .Lbegin_fields
.Lruntime_ref:
    shr eax, 4
    lea rdx, [rip+.Lref_tags-5]
    movzx eax, byte ptr [rdx+rax]
    call .Lnewframe
    mov byte ptr [rbx+F_KIND], K_REF
    mov [rbx+F_TAG], al
    mov eax, 1
    jmp .Lbegin_fields

.Lexpr_tag:
    cmp al, 0x20
    je .Lnormal
    cmp al, 0x5f
    ja .Lfail
    cmp al, 0x20
    ja .Lexpr_app
    cmp al, 0x10
    jb .Lexpr_fixed
    cmp al, 0x18
    jb .Lfail
.Lexpr_fixed:
    call .Lnewframe
    mov [rbx+F_OPCODE], al
    lea rsi, [rip+.Lexpr_schema]
    mov edx, [rsi+rax*4]
    mov [rbx+F_TAG], dl
    mov [rbx+F_MODES], dh
    shr edx, 16
    movzx eax, dl                    # arity
    movzx edx, dh                    # scalar u64 count
    mov [rbx+F_SCALARS], dx
    jmp .Lexpr_fields
.Lexpr_app:
    call .Lnewframe
    cmp al, 0x40
    jae .Lconst_head
    sub eax, 0x21
    mov [rbx+F_APPS], al
    mov byte ptr [rbx+F_OPCODE], 0x21
    mov byte ptr [rbx+F_TAG], 5
    mov byte ptr [rbx+F_MODES], 3
    jmp .Lapplication_fields
.Lconst_head:
    sub eax, 0x40
    mov [rbx+F_APPS], al
    mov byte ptr [rbx+F_OPCODE], 0x40
    mov byte ptr [rbx+F_TAG], 4
    mov byte ptr [rbx+F_MODES], 1
.Lapplication_fields:
    mov word ptr [rbx+F_SCALARS], 1
    mov eax, 2
.Lexpr_fields:
    mov byte ptr [rbx+F_KIND], K_EXPR
.Lbegin_fields:
    mov [rbx+F_FIELDS], rax
    mov [rbx+F_LEFT], rax
    test rax, rax
    jz .Lemit
.Lnext_child:
    shr byte ptr [rbx+F_MODES], 1
    jc .Lexprish
    jmp .Lnormal

.Ldone_value:
    cmp qword ptr [rbp+FRAME_BYTES], 0
    je .Lroot
    cmp byte ptr [rbx+F_KIND], K_SAVE
    je .Lsave_value
    mov rcx, [rbp+VALUE_BYTES]
    cmp rcx, [rbp+VALUES+8]
    jae .Lgrow_values
.Lpush_value:
    mov rdx, [rbp+VALUES]
    mov [rdx+rcx], rax
    add rcx, 8
    mov [rbp+VALUE_BYTES], rcx
    dec qword ptr [rbx+F_LEFT]
    jnz .Lnext_child

.Lemit:
    movzx eax, byte ptr [rbx+F_KIND]
    cmp eax, K_ARRAY
    je .Lemit_array
    cmp eax, K_REF
    je .Lemit_ref
    cmp eax, K_EXPR
    jne .Lemit_ctor
    # Compute omitted cached data while all referenced children are complete.
    lea rax, [rbp+SCALAR]
    sub rsp, 16
    mov [rsp], rax
    movzx edi, byte ptr [rbx+F_OPCODE]
    mov rsi, [rbp+VALUES]
    add rsi, [rbx+F_START]
    mov rdx, r14
    mov rcx, r15
    mov r8, [rbp+BASE]
    mov r9d, [rbp+GMP]
    call lgz_expr_data
    add rsp, 16
    test eax, eax
    jnz .Lfail
.Lemit_ctor:
    movzx eax, word ptr [rbx+F_SCALARS]
    add rax, [rbx+F_FIELDS]
    lea rax, [rax*8+8]
    mov [rbp+AUX], rax
    call .Lreserve
    mov [rbp+RESULT], rax
    mov eax, [rbp+AUX]
    mov [rdi+4], ax
    mov eax, [rbx+F_FIELDS]
    mov [rdi+6], al
    mov al, [rbx+F_TAG]
    mov [rdi+7], al
    add rdi, 8
    call .Lcopy_fields
    cmp byte ptr [rbx+F_KIND], K_EXPR
    je .Lemit_metadata
    movzx ecx, word ptr [rbx+F_SCALARS]
    test ecx, ecx
    jz .Lpop_result
    shl ecx, 3
    input_need rcx
    mov rsi, r12
    add r12, rcx
    cmp ecx, 8
    jne .Lcopy_scalars
    movsq
    jmp .Lpop_result
.Lcopy_scalars:
    shr ecx, 3
    rep movsq
    jmp .Lpop_result
.Lemit_metadata:
    mov rax, [rbp+SCALAR]
    stosq
    cmp word ptr [rbx+F_SCALARS], 2
    jne .Lmore_apps
    movzx eax, byte ptr [rbx+F_OPCODE]
    cmp eax, 0x10
    jb .Llet_flag
    and eax, 3
    jmp .Lemit_flag
.Llet_flag:
    and eax, 1
.Lemit_flag:
    stosq
.Lmore_apps:
    cmp byte ptr [rbx+F_APPS], 0
    je .Lpop_result
    dec byte ptr [rbx+F_APPS]
    mov byte ptr [rbx+F_OPCODE], 0x21
    mov byte ptr [rbx+F_TAG], 5
    mov byte ptr [rbx+F_MODES], 1
    mov qword ptr [rbx+F_LEFT], 1
    mov rdx, [rbx+F_START]
    mov rdi, [rbp+VALUES]
    mov rax, [rbp+RESULT]
    mov [rdi+rdx], rax
    add rdx, 8
    mov [rbp+VALUE_BYTES], rdx
    jmp .Lnext_child
.Lemit_array:
    mov rax, [rbx+F_FIELDS]
    lea rax, [rax*8+24]
    call .Lreserve
    mov [rbp+RESULT], rax
    mov byte ptr [rdi+4], 1
    mov byte ptr [rdi+7], 246
    mov rax, [rbx+F_FIELDS]
    mov [rdi+8], rax
    mov [rdi+16], rax
    add rdi, 24
    call .Lcopy_fields
    jmp .Lpop_result
.Lemit_ref:
    movzx ecx, byte ptr [rbx+F_TAG]
    mov eax, 16
    cmp ecx, 251                    # thunk and task append a zero impl slot
    jb .Lsize_ref
    cmp ecx, 252
    ja .Lsize_ref
    mov eax, 24
.Lsize_ref:
    mov [rbp+AUX], eax
    call .Lreserve
    mov [rbp+RESULT], rax
    mov eax, [rbp+AUX]
    mov [rdi+4], ax
    mov al, [rbx+F_TAG]
    mov [rdi+7], al
    add rdi, 8
    call .Lcopy_fields
.Lpop_result:
    mov rax, [rbp+RESULT]
.Lpop_frame:
    sub rbx, F_SIZE
    sub qword ptr [rbp+FRAME_BYTES], F_SIZE
    jmp .Ldone_value

.Lsave_value:
    mov rcx, [rbp+REF_BYTES]
    cmp rcx, [rbp+REFERENCES+8]
    jae .Lgrow_refs
.Lpush_ref:
    mov rdx, [rbp+REFERENCES]
    mov [rdx+rcx], rax
    add rcx, 8
    mov [rbp+REF_BYTES], rcx
    jmp .Lpop_frame
.Lgrow_values:
    push rax
    lea rsi, [rcx+8]
    lea rdi, [rbp+VALUES]
    call .Lensure
    pop rax
    mov rcx, [rbp+VALUE_BYTES]
    jmp .Lpush_value
.Lgrow_refs:
    push rax
    lea rsi, [rcx+8]
    lea rdi, [rbp+REFERENCES]
    call .Lensure
    pop rax
    mov rcx, [rbp+REF_BYTES]
    jmp .Lpush_ref

.Lscalar_array:
    call .Lread_int
    test rax, rax
    js .Lfail
    input_need rax
    mov [rbp+DATA_LEN], rax
    add rax, 7
    and rax, -8
    add rax, 24
    call .Lreserve
    mov byte ptr [rdi+4], 1
    mov byte ptr [rdi+7], 248
    mov rcx, [rbp+DATA_LEN]
    mov [rdi+8], rcx
    mov [rdi+16], rcx
    add rdi, 24
    jmp .Lcopy_payload
.Lstring:
    mov rsi, r12
    xor ecx, ecx
.Lstring_scan:
    cmp rsi, r13
    jae .Lfail
    movzx eax, byte ptr [rsi]
    inc rsi
    test al, al
    jz .Lstring_end
    and al, 0xc0
    cmp al, 0x80
    je .Lstring_scan
    inc rcx
    jmp .Lstring_scan
.Lstring_end:
    sub rsi, r12
    mov [rbp+DATA_LEN], rsi
    mov [rbp+AUX], rcx
    lea rax, [rsi+7]
    and rax, -8
    add rax, 32
    call .Lreserve
    mov byte ptr [rdi+4], 1
    mov byte ptr [rdi+7], 249
    mov rcx, [rbp+DATA_LEN]
    mov [rdi+8], rcx
    mov [rdi+16], rcx
    mov rsi, [rbp+AUX]
    mov [rdi+24], rsi
    add rdi, 32
.Lcopy_payload:
    mov rsi, r12
    add r12, rcx
    rep movsb
    jmp .Ldone_value
.Lmpz:
    call .Lread_int
    mov [rbp+AUX], eax
    and eax, 0x7fffffff             # v0.1.15 stores this many 64-bit limbs
    test eax, eax
    jz .Lfail
    shl rax, 3
    input_need rax
    mov [rbp+DATA_LEN], rax
    cmp byte ptr [rbp+GMP], 0
    je .Lmpz_portable
    add rax, 24
    call .Lreserve
    mov byte ptr [rdi+7], 250
    mov ecx, [rbp+AUX]
    mov [rdi+12], ecx
    and ecx, 0x7fffffff
    mov [rdi+8], ecx
    mov rcx, [rbp+DATA_LEN]
    lea edx, [rcx+24]
    mov [rdi+4], dx
    lea rdx, [rax+24]
    mov [rdi+16], rdx
    add rdi, 24
    jmp .Lcopy_payload
.Lmpz_portable:
    add rax, 32
    call .Lreserve
    mov byte ptr [rdi+7], 250
    mov edx, [rbp+AUX]
    shr edx, 31
    mov [rdi+8], rdx
    mov rcx, [rbp+DATA_LEN]
    mov rdx, rcx
    shr rdx, 2
    cmp dword ptr [r12+rcx-4], 1
    sbb rdx, 0
    mov [rdi+16], rdx
    lea edx, [rdx*4+32]
    mov [rdi+4], dx
    lea rdx, [rax+32]
    mov [rdi+24], rdx
    add rdi, 32
    jmp .Lcopy_payload

.Lroot:
    cmp r12, r13
    jne .Lfail
    mov rdx, [rbp+FIXUP]
    mov [r14+rdx], rax
    # Return exactly the pages covering the output. Drop unused capacity.
    lea rsi, [r15+4095]
    and rsi, -4096
    mov rdx, [rbp+OUTPUT+8]
    sub rdx, rsi
    jz .Lpublish
    lea rdi, [r14+rsi]
    mov rsi, rdx
    mov eax, 11
    syscall
.Lpublish:
    mov rdi, [rbp+OUT_PARAM]
    mov [rdi], r14
    mov rdi, [rbp+LEN_PARAM]
    mov [rdi], r15
    mov qword ptr [rbp+OUTPUT], 0
    xor ebx, ebx
    jmp .Lcleanup
.Lfail:
    mov ebx, -1
.Lcleanup:
    mov rsp, rbp
    mov r12, rbp
    lea r13, [rbp+BASE]
.Lrelease:
    mov rdi, [r12]
    test rdi, rdi
    jz .Lrelease_next
    mov rsi, [r12+8]
    mov eax, 11
    syscall
.Lrelease_next:
    add r12, 16
    cmp r12, r13
    jb .Lrelease
    mov eax, ebx
    add rsp, CTX_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size lgz_decode,.-lgz_decode

# Grow an anonymous mapping to at least rsi bytes. Old data survives relocation.
# rdi = descriptor, rax = possibly new location; clobbers caller-saved regs.
.Lensure:
    test rsi, rsi
    js .Lfail
    cmp rsi, [rdi+8]
    jbe .Lcapacity_ok
    mov r8, rdi
    mov rdx, [rdi+8]
    add rdx, rdx
    cmp rdx, rsi
    cmovb rdx, rsi
    add rdx, 4095
    jc .Lfail
    and rdx, -4096
    test rdx, rdx
    jle .Lfail
    mov rsi, [rdi+8]
    test rsi, rsi
    jz .Lmap_new
    mov rdi, [r8]
    mov r10d, 1                     # MREMAP_MAYMOVE
    mov eax, 25
    syscall
    jmp .Lmap_result
.Lmap_new:
    mov rsi, rdx
    push r8                         # mmap uses r8 for its fd
    call .Lmap_anonymous
    pop r8
    mov rdx, rsi
.Lmap_result:
    cmp rax, -4095
    jae .Lfail
    mov [r8], rax
    mov [r8+8], rdx
    ret
.Lcapacity_ok:
    mov rax, [rdi]
    ret

.Lmap_anonymous:
    xor edi, edi
    mov edx, 3                     # PROT_READ | PROT_WRITE
    mov r10d, 0x22                 # MAP_PRIVATE | MAP_ANONYMOUS
    mov r8d, -1
    xor r9d, r9d
    mov eax, 9
    syscall
    ret

# Reserve rax bytes in output. rdi receives writable memory and rax the
# virtual .olean address. Only offsets survive a later reserve.
.Lreserve:
    lea rsi, [r15+rax]
    cmp rsi, r15
    jb .Lfail
    cmp rsi, [rbp+OUTPUT+8]
    ja .Lgrow_output
.Lspace_ready:
    lea rdi, [r14+r15]
    mov rax, [rbp+BASE]
    add rax, r15
    jc .Lfail
    mov r15, rsi
    ret
.Lgrow_output:
    mov [rbp+NEXT_SIZE], rsi
    lea rdi, [rbp+OUTPUT]
    call .Lensure
    mov r14, rax
    mov rsi, [rbp+NEXT_SIZE]
    jmp .Lspace_ready

# Keep the opcode in eax across this helper, including a mapping relocation.
.Lnewframe:
    mov rcx, [rbp+FRAME_BYTES]
    cmp rcx, [rbp+FRAMES+8]
    jae .Lgrow_frames
.Lframe_ready:
    mov rbx, [rbp+FRAMES]
    add rbx, rcx
    add rcx, F_SIZE
    mov [rbp+FRAME_BYTES], rcx
    mov qword ptr [rbx], 0
    mov rcx, [rbp+VALUE_BYTES]
    mov [rbx+F_START], rcx
    ret
.Lgrow_frames:
    push rax
    lea rsi, [rcx+F_SIZE]
    lea rdi, [rbp+FRAMES]
    call .Lensure
    pop rax
    mov rcx, [rbp+FRAME_BYTES]
    jmp .Lframe_ready

# Copy this frame's field values to rdi and pop them from the pending stack.
.Lcopy_fields:
    mov rdx, [rbx+F_START]
    mov rsi, [rbp+VALUES]
    add rsi, rdx
    mov [rbp+VALUE_BYTES], rdx
    mov rcx, [rbx+F_FIELDS]
    cmp rcx, 4
    ja .Lcopy_many
    test ecx, ecx
    jz .Lcopied
    movsq
    cmp ecx, 1
    je .Lcopied
    movsq
    cmp ecx, 2
    je .Lcopied
    movsq
    cmp ecx, 3
    je .Lcopied
    movsq
.Lcopied:
    ret
.Lcopy_many:
    rep movsq
    ret

.Lread_int:
    input_need 1
    movzx eax, byte ptr [r12]
    inc r12
.Lint_tag:
    cmp eax, 0xd0
    jb .Lfail
    cmp eax, 0xef
    ja .Lint_wide
    sub eax, 0xd0
    ret
.Lint_wide:
    cmp eax, 0xf8
    je .Lint8
    cmp eax, 0xf9
    je .Lint16
    cmp eax, 0xfa
    je .Lint32
    cmp eax, 0xfb
    jne .Lfail
    input_need 8
    mov rax, [r12]
    add r12, 8
    ret
.Lint8:
    input_need 1
    movsx rax, byte ptr [r12]
    inc r12
    ret
.Lint16:
    input_need 2
    movsx rax, word ptr [r12]
    add r12, 2
    ret
.Lint32:
    input_need 4
    movsxd rax, dword ptr [r12]
    add r12, 4
    ret

# Decimal version component from a u8, advancing rdi.
.Ldecimal:
    mov ecx, 10
    xor edx, edx
    div ecx
    push rdx
    test eax, eax
    jz .Ldigit
    call .Ldecimal
.Ldigit:
    pop rax
    add al, '0'
    stosb
    ret

.section .rodata
.Lref_tags: .byte 251,252,253,0,244
# tag, child-mode mask, pointer fields, scalar words; indexed by exprish opcode.
.Lexpr_schema:
    .byte 1,1,2,1      # Name.str
    .byte 2,1,2,1      # Name.num
    .byte 1,1,1,1      # Level.succ
    .byte 2,3,2,1      # Level.max
    .byte 3,3,2,1      # Level.imax
    .byte 4,1,1,1      # Level.param
    .byte 5,1,1,1      # Level.mvar
    .byte 0,0,1,1      # Expr.bvar
    .byte 1,1,1,1      # Expr.fvar
    .byte 2,1,1,1      # Expr.mvar
    .byte 3,1,1,1      # Expr.sort
    .byte 9,0,1,1      # Expr.lit
    .byte 10,2,2,1     # Expr.mdata
    .byte 11,5,3,1     # Expr.proj
    .byte 8,15,4,2     # Expr.letE (two flag values)
    .byte 8,15,4,2
    .zero 8*4
    .rept 4
    .byte 6,7,3,2      # Expr.lam
    .endr
    .rept 4
    .byte 7,7,3,2      # Expr.forallE
    .endr
.section .note.GNU-stack,"",@progbits
