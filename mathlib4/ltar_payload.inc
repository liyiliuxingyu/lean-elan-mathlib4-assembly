# SPDX-License-Identifier: Apache-2.0
# Member selection, decoding and queries for the mathlib-ltar entry point.
.pushsection .rodata
.Ljson_prefix: .ascii "{\"log\":[],\"depHash\":\""
.equ JSON_PREFIX_BYTES, .-.Ljson_prefix
.Ljson_suffix: .ascii "\"}"
.Lmissing_member_msg: .ascii "mathlib-ltar: member not found\n"
.equ MISSING_MEMBER_BYTES, .-.Lmissing_member_msg
.Lambiguous_msg: .ascii "mathlib-ltar: more than one member matches\n"
.equ AMBIGUOUS_BYTES, .-.Lambiguous_msg
.Lno_olean_msg: .ascii "mathlib-ltar: archive contains no LGZ .olean member\n"
.equ NO_OLEAN_BYTES, .-.Lno_olean_msg
.Ldecode_msg: .ascii "mathlib-ltar: invalid or unsupported compressed member\n"
.equ DECODE_ERROR_BYTES, .-.Ldecode_msg
.Lcache_msg: .ascii "mathlib-ltar: incompatible or malformed .olean image\n"
.equ CACHE_ERROR_BYTES, .-.Lcache_msg
.Lquery_msg: .ascii "mathlib-ltar: invalid qualified name\n"
.equ QUERY_ERROR_BYTES, .-.Lquery_msg
.Lterm_msg: .ascii "mathlib-ltar: --term requires a theorem declared in this module\n"
.equ TERM_ERROR_BYTES, .-.Lterm_msg
.Lterm_data_msg: .ascii "mathlib-ltar: invalid or unsupported term data\n"
.equ TERM_DATA_BYTES, .-.Lterm_data_msg
.Lwork_msg: .ascii "mathlib-ltar: cannot allocate term workspace\n"
.equ WORK_BYTES_MSG, .-.Lwork_msg
.balign 4
.Lquery_names:
    .long .Lq_axiom-.Lquery_names, .Lq_definition-.Lquery_names
    .long .Lq_theorem-.Lquery_names, .Lq_opaque-.Lquery_names
    .long .Lq_quotient-.Lquery_names, .Lq_inductive-.Lquery_names
    .long .Lq_constructor-.Lquery_names, .Lq_recursor-.Lquery_names
    .long .Lq_missing-.Lquery_names
.Lq_axiom:        .asciz "axiom\t"
.Lq_definition:   .asciz "definition\t"
.Lq_theorem:      .asciz "theorem\t"
.Lq_opaque:       .asciz "opaque\t"
.Lq_quotient:     .asciz "quotient\t"
.Lq_inductive:    .asciz "inductive\t"
.Lq_constructor:  .asciz "constructor\t"
.Lq_recursor:     .asciz "recursor\t"
.Lq_missing:      .asciz "missing\t"
.popsection

.pushsection .bss
.balign 8
.Larguments:      .skip 8
.Larg_count:      .skip 8
.Lmatch_count:    .skip 8
.Lselected_kind:  .skip 8
.Lselected_data:  .skip 8
.Lselected_size:  .skip 8
.Lzstd_buffer:    .skip 8
.Lzstd_length:    .skip 8
.Lolean_buffer:   .skip 8
.Lolean_length:   .skip 8
.Lview:           .skip VIEW_BYTES
.Lresult:         .skip RESULT_BYTES
.popsection

# mathlib_ltar_walk callback(wanted_path, kind, name, name_length, data, size).
.Lselect_exact:
    cmp esi, 5                         # comments are not named members
    je .Lselect_done
    mov r10d, esi
    mov rsi, rdx                       # include the path terminator in equality
    inc rcx
    repe cmpsb
    jne .Lselect_done
    inc qword ptr [rip+.Lmatch_count]
    mov [rip+.Lselected_data], r8
    mov [rip+.Lselected_size], r9
    mov [rip+.Lselected_kind], r10
.Lselect_done:
    ret

# Directory and unique selection were validated before reaching this point.
.Lhandle_payload:
    mov rdi, [rip+.Lselected_data]
    mov rsi, [rip+.Lselected_size]
    cmp ebx, 2
    jae .Lhash_member
    test ebx, ebx
    jnz .Ldecode_olean
    xor edx, edx                       # generic Zstandard members use no dictionary
    xor ecx, ecx
    lea r8, [rip+.Lzstd_buffer]
    lea r9, [rip+.Lzstd_length]
    call mathlib_ltar_zstd_stream
    test eax, eax
    jnz .Ldecode_error
    mov rsi, [rip+.Lzstd_buffer]
    mov rdx, [rip+.Lzstd_length]
    jmp .Lcat_bytes
.Ldecode_olean:
    lea rdx, [rip+.Lolean_buffer]
    lea rcx, [rip+.Lolean_length]
    call mathlib_ltar_decode_olean
    test eax, eax
    jnz .Ldecode_error
    mov rsi, [rip+.Lolean_buffer]
    mov rdx, [rip+.Lolean_length]
    cmp r15d, MODE_CAT
    jne .Lquery_image
.Lcat_bytes:
    call .Lwrite                     # large member output bypasses TSV buffer
    xor edi, edi
    jmp .Lexit

.Lhash_member:
    mov rbp, [rdi]
    cmp ebx, 3
    jne .Lhash_digits
    lea rsi, [rip+.Ljson_prefix]
    mov edx, JSON_PREFIX_BYTES
    call .Lput
.Lhash_digits:
    mov rax, rbp
    call .Ldecimal_text
    cmp ebx, 3
    jne .Lpayload_finish
    lea rsi, [rip+.Ljson_suffix]
    mov edx, 2
    call .Lput
.Lpayload_finish:
    call .Lflush
    xor edi, edi
    jmp .Lexit

.Lquery_image:
    mov rdi, rsi
    mov rsi, rdx
    lea rdx, [rip+.Lview]
    call mathlib_olean_parse
    cmp eax, 1
    jne .Lcache_error
    mov rbx, [rip+.Larguments]
    mov r13, [rip+.Larg_count]
    lea rdi, [rip+.Lview]
    mov rsi, r13
    call mathlib_olean_index_new
    mov rbp, rax
    xor r12d, r12d                   # exit status, set to 1 for a missing name
.Lnext_query:
    lea rdi, [rip+.Lview]
    mov rsi, [rbx]
    lea rdx, [rip+.Lresult]
    mov rcx, rbp
    call mathlib_olean_lookup_index
    test eax, eax
    jz .Lquery_missing
    cmp eax, -1
    je .Lquery_error
    cmp eax, 1
    jne .Lcache_error
    mov rax, [rip+.Lresult+RESULT_KIND]
    cmp rax, 7
    ja .Lcache_error
    cmp r15d, MODE_TERM
    jne .Lquery_row
    cmp eax, 2
    jne .Lnot_theorem
    lea rdi, [rip+.Lview]
    mov rsi, [rip+.Lresult+RESULT_TYPE]
    mov rdx, [rip+.Lresult+RESULT_PROOF]
    call mathlib_olean_dump_term
    test eax, eax
    jz .Lquery_done
    cmp eax, -2
    je .Lwrite_error
    cmp eax, -3
    je .Lterm_workspace
    lea rsi, [rip+.Lterm_data_msg]
    mov edx, TERM_DATA_BYTES
    jmp .Lerror
.Lquery_missing:
    mov r12d, 1
    mov eax, 8
.Lquery_row:
    lea rsi, [rip+.Lquery_names]
    movsxd rax, dword ptr [rsi+rax*4]
    add rsi, rax
    call .Lput_cstr
    mov rsi, [rbx]
    call .Lput_cstr
    call .Lnewline
    add rbx, 8
    dec r13
    jnz .Lnext_query
.Lquery_done:
    mov rdi, rbp
    call mathlib_olean_index_free
    call .Lflush
    mov edi, r12d
    jmp .Lexit
.Lput_cstr:
    xor edx, edx
.Lcstr_length:
    cmp byte ptr [rsi+rdx], 0
    je .Lput
    inc rdx
    jmp .Lcstr_length

.Lambiguous:
    lea rsi, [rip+.Lambiguous_msg]
    mov edx, AMBIGUOUS_BYTES
    jmp .Lerror
.Lno_match:
    lea rsi, [rip+.Lmissing_member_msg]
    mov edx, MISSING_MEMBER_BYTES
    mov r8d, 1
    jmp .Lreport
.Lno_olean:
    lea rsi, [rip+.Lno_olean_msg]
    mov edx, NO_OLEAN_BYTES
    jmp .Lerror
.Ldecode_error:
    lea rsi, [rip+.Ldecode_msg]
    mov edx, DECODE_ERROR_BYTES
    jmp .Lerror
.Lcache_error:
    call .Lflush
    lea rsi, [rip+.Lcache_msg]
    mov edx, CACHE_ERROR_BYTES
    jmp .Lerror
.Lquery_error:
    call .Lflush
    lea rsi, [rip+.Lquery_msg]
    mov edx, QUERY_ERROR_BYTES
    jmp .Lerror
.Lnot_theorem:
    lea rsi, [rip+.Lterm_msg]
    mov edx, TERM_ERROR_BYTES
    jmp .Lerror
.Lterm_workspace:
    lea rsi, [rip+.Lwork_msg]
    mov edx, WORK_BYTES_MSG
    jmp .Lerror
