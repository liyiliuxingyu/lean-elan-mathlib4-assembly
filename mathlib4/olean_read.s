# SPDX-License-Identifier: Apache-2.0
# Lean 4.19.0 compacted module reader. File pointers are converted to
# offsets before use; the image can be mapped at any virtual address.
.intel_syntax noprefix
.include "olean_layout.inc"

.equ HEADER_BYTES, 96
.equ NAME_COMPONENT_LIMIT, 64
.equ NAME_COMPONENT_BYTES, 16
.equ LOOKUP_INDEX, NAME_COMPONENT_LIMIT * NAME_COMPONENT_BYTES
.equ LOOKUP_FIRST, LOOKUP_INDEX + 8
.equ NAME_STACK_BYTES, LOOKUP_FIRST + 16

.section .rodata
.Llean_commit:
    .ascii "6caaee842e9495688c1567e78c0e68dbb96942aa"

.text
.globl mathlib_olean_parse
.type mathlib_olean_parse, @function
# rdi = image, rsi = image size, rdx = view. Returns 1 or 0.
mathlib_olean_parse:
    cmp rsi, HEADER_BYTES
    jb .Lbad_header
    cmp dword ptr [rdi], 0x61656c6f   # "olea"
    jne .Lbad_header
    cmp word ptr [rdi + 4], 0x026e  # "n", format 2
    jne .Lbad_header
    cmp byte ptr [rdi + 6], 1      # GMP, as in the pinned release
    jne .Lbad_header
    lea r8, [rip + .Llean_commit]
    xor ecx, ecx
.Lcommit_check:
    mov rax, [r8 + rcx]
    cmp [rdi + rcx + 40], rax
    jne .Lbad_header
    add ecx, 8
    cmp ecx, 40
    jb .Lcommit_check

    mov rax, rdi
    add rax, rsi
    jc .Lbad_header
    mov rax, [rdi + 80]
    test rax, rax
    jz .Lbad_header
    test al, 7
    jnz .Lbad_header
    mov [rdx + VIEW_MAPPING], rdi
    mov [rdx + VIEW_SIZE], rsi
    mov [rdx + VIEW_BASE], rax

    push r12
    mov rax, [rdi + 88]
    mov rdi, rdx
    mov r10d, 48
    call .Lpointer
    test rax, rax
    jz .Lbad_view
    cmp word ptr [rax + 6], 0x0005  # ModuleData, five object fields
    jne .Lbad_view
    mov r12, rax

    mov rax, [r12 + 8]
    call .Larray
    test rax, rax
    jz .Lbad_view
    mov [rdi + VIEW_IMPORTS], r10
    add rax, 24
    mov [rdi + VIEW_IMPORT_DATA], rax

    mov rax, [r12 + 16]
    call .Larray
    test rax, rax
    jz .Lbad_view
    mov [rdi + VIEW_COUNT], r10
    add rax, 24
    mov [rdi + VIEW_NAMES], rax

    mov rax, [r12 + 24]
    call .Larray
    test rax, rax
    jz .Lbad_view
    cmp [rdi + VIEW_COUNT], r10
    jne .Lbad_view
    add rax, 24
    mov [rdi + VIEW_CONSTANTS], rax
    mov eax, 1
    jmp .Lview_done
.Lbad_view:
    xor eax, eax
.Lview_done:
    pop r12
    ret
.Lbad_header:
    xor eax, eax
    ret
.size mathlib_olean_parse, . - mathlib_olean_parse

# Public checked translation for readers of typed cached objects.
.globl mathlib_olean_object
.type mathlib_olean_object, @function
# rdi = view, rsi = serialized pointer, rdx = minimum byte length.
mathlib_olean_object:
    mov rax, rsi
    mov r10, rdx
    jmp .Lpointer
.size mathlib_olean_object, .-mathlib_olean_object

# rdi = view, rax = serialized pointer, r10 = required length.
# Returns rax = mapped pointer or 0; clobbers rcx only besides rax.
.Lpointer:
    sub rax, [rdi + VIEW_BASE]
    jc .Lbad_pointer
    cmp rax, HEADER_BYTES
    jb .Lbad_pointer
    test al, 7
    jnz .Lbad_pointer
    mov rcx, [rdi + VIEW_SIZE]
    sub rcx, r10
    jc .Lbad_pointer
    cmp rax, rcx
    ja .Lbad_pointer
    add rax, [rdi + VIEW_MAPPING]
    ret
.Lbad_pointer:
    xor eax, eax
    ret

# As with .Lpointer, sets r10 to the array length on success.
.Larray:
    sub rsp, 8
    mov r10d, 24
    call .Lpointer
    add rsp, 8
    test rax, rax
    jz .Lbad_pointer
    cmp byte ptr [rax + 7], 246     # LeanArray
    jne .Lbad_pointer
    mov r10, [rax + 8]
    cmp r10, [rax + 16]
    ja .Lbad_pointer
    mov rcx, [rdi + VIEW_MAPPING]
    add rcx, [rdi + VIEW_SIZE]
    sub rcx, rax
    sub rcx, 24
    shr rcx, 3
    cmp r10, rcx
    ja .Lbad_pointer
    ret

.globl mathlib_olean_import_path
.type mathlib_olean_import_path, @function
# rdi = view, rsi = import index, rdx = output buffer, rcx = capacity.
# Returns length excluding NUL, -1 for index/capacity, -2 for malformed
# metadata, or -3 for a runtime-only import. Output is defined on success.
mathlib_olean_import_path:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rdx
    mov r15, rdx
    add r15, rcx
    jc .Limport_capacity
    cmp rsi, [rdi + VIEW_IMPORTS]
    jae .Limport_capacity
    mov rax, [rdi + VIEW_IMPORT_DATA]
    mov rax, [rax + rsi * 8]
    mov r10d, 17
    call .Lpointer
    test rax, rax
    jz .Limport_malformed
    cmp word ptr [rax + 6], 0x0001  # Import: one object field, then Bool
    jne .Limport_malformed
    movzx ecx, byte ptr [rax + 16]
    cmp ecx, 1
    je .Limport_runtime
    ja .Limport_malformed
    mov rbx, [rax + 8]

    # Name prefixes are stored from leaf to root. Build the path in the
    # same order at the buffer end, then copy it forward to the start.
    mov r14, r15
    sub r14, r13
    cmp r14, 7
    jb .Limport_capacity
    lea r14, [r15 - 7]
    mov dword ptr [r14], 0x656c6f2e # ".ole"
    mov word ptr [r14 + 4], 0x6e61  # "an"
    mov byte ptr [r14 + 6], 0

.Limport_component:
    mov rax, rbx
    mov r10d, 32
    call .Lpointer
    test rax, rax
    jz .Limport_malformed
    cmp word ptr [rax + 6], 0x0102  # Name.str, two object fields
    jne .Limport_malformed
    cmp rbx, [rax + 8]
    je .Limport_malformed
    mov rbx, [rax + 8]
    mov rax, [rax + 16]
    call .Lpointer                  # LeanString header is also 32 bytes
    test rax, rax
    jz .Limport_malformed
    cmp byte ptr [rax + 7], 249     # LeanString
    jne .Limport_malformed
    mov rcx, [rax + 8]
    cmp rcx, 2                     # Nonempty component plus NUL
    jb .Limport_malformed
    lea rsi, [rax + 32]
    mov r9, [r12 + VIEW_MAPPING]
    add r9, [r12 + VIEW_SIZE]
    sub r9, rsi
    cmp rcx, r9
    ja .Limport_malformed
    dec rcx
    cmp byte ptr [rsi + rcx], 0
    jne .Limport_malformed

    # Whole "." and ".." components would change path semantics.
    cmp rcx, 2
    ja .Limport_budget
    cmp byte ptr [rsi], '.'
    jne .Limport_budget
    cmp rcx, 1
    je .Limport_malformed
    cmp byte ptr [rsi + 1], '.'
    je .Limport_malformed

.Limport_budget:
    mov rax, r14
    sub rax, r13
    cmp rbx, 1                     # Name.anonymous ends the chain
    je .Limport_check_size
    sub rax, 1                     # Slash between this name and its prefix
    jc .Limport_capacity
.Limport_check_size:
    cmp rcx, rax
    ja .Limport_capacity

    mov r8, rsi
    lea r9, [rsi + rcx]
.Limport_check_byte:
    mov al, [r8]
    cmp al, 0x20                   # Includes embedded NUL
    jb .Limport_malformed
    cmp al, '/'
    je .Limport_malformed
    cmp al, 0x7f
    je .Limport_malformed
    inc r8
    cmp r8, r9
    jb .Limport_check_byte

    sub r14, rcx
    mov rdi, r14
    rep movsb
    cmp rbx, 1
    je .Limport_copy_result
    dec r14
    mov byte ptr [r14], '/'
    mov rdi, r12
    jmp .Limport_component

.Limport_copy_result:
    mov rax, r15
    sub rax, r14
    dec rax                        # Exclude NUL from the result length
    cmp rax, 0x7fffffff
    ja .Limport_capacity
    lea rcx, [rax + 1]
    mov rsi, r14
    mov rdi, r13
    rep movsb                      # Destination is at or before source
    jmp .Limport_done
.Limport_capacity:
    mov eax, -1
    jmp .Limport_done
.Limport_malformed:
    mov eax, -2
    jmp .Limport_done
.Limport_runtime:
    mov eax, -3
.Limport_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.size mathlib_olean_import_path, . - mathlib_olean_import_path

.globl mathlib_olean_lookup
.type mathlib_olean_lookup, @function
# rdi = view, rsi = NUL-terminated name, rdx = result.
# Returns 1 found, 0 missing, -1 invalid name, -2 invalid cache.
mathlib_olean_lookup:
    xor ecx, ecx
    jmp mathlib_olean_lookup_index
.size mathlib_olean_lookup, .-mathlib_olean_lookup

.globl mathlib_olean_lookup_index
.type mathlib_olean_lookup_index,@function
# Same ABI as lookup with optional index for this view in rcx.
mathlib_olean_lookup_index:
    xor r8d, r8d
    jmp mathlib_olean_lookup_cached
.size mathlib_olean_lookup_index, .-mathlib_olean_lookup_index

.globl mathlib_olean_lookup_cached
.hidden mathlib_olean_lookup_cached
.type mathlib_olean_lookup_cached,@function
# r8 = nullable, initially zeroed QUERY_BYTES stable storage for this argv.
# Components borrow the unchanged name text for subsequent module lookups.
mathlib_olean_lookup_cached:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, NAME_STACK_BYTES
    mov [rsp + LOOKUP_INDEX], rcx
    mov r12, rdi
    mov r13, rdx
    mov qword ptr [r13 + RESULT_KIND], 0
    mov qword ptr [r13 + RESULT_RECORD], 0
    mov qword ptr [r13 + RESULT_TYPE], 0
    mov qword ptr [r13 + RESULT_PROOF], 0

    mov rdi, rsi
    mov rsi, rsp
    test r8, r8
    jz .Lparse_components
    lea rsi, [r8 + QUERY_COMPONENTS]
    mov eax, [r8]
    test eax, eax
    jnz .Lcomponents_ready
.Lparse_components:
    mov r15, rsi
    call mathlib_olean_parse_query
    test eax, eax
    jz .Lbad_query
    mov rsi, r15
    cmp rsi, rsp
    je .Lcomponents_ready
    mov [rsi - QUERY_COMPONENTS], eax
.Lcomponents_ready:
    mov [rsp + LOOKUP_FIRST], rsi
    mov r14d, eax
    shl r14, 4
    lea r14, [rsi + r14 - NAME_COMPONENT_BYTES]  # Last component.
    xor ebx, ebx
    mov r15, [rsp + LOOKUP_INDEX]
    test r15, r15
    jz .Lcandidate
    mov rdi, [r14]
    mov rsi, [r14 + 8]
    call mathlib_olean_leaf_hash
    and eax, [r15 + INDEX_MASK]
    mov ebx, [r15 + rax*4 + INDEX_HEADS]
.Lindexed_candidate:
    test ebx, ebx
    jz .Lmissing
    dec ebx
.Lcandidate:
    cmp rbx, [r12 + VIEW_COUNT]
    jae .Lmissing
    mov rax, [r12 + VIEW_NAMES]
    mov rbp, [rax + rbx * 8]
    mov r15, r14

.Lcomponent:
    cmp rbp, 1                      # Name.anonymous
    je .Lnext_candidate
    mov rax, rbp
    mov rdi, r12
    mov r10d, 32
    call .Lpointer
    test rax, rax
    jz .Lbad_cache
    cmp byte ptr [rax + 6], 2
    jne .Lbad_cache
    mov rbp, [rax + 8]              # next outer prefix
    movzx ecx, byte ptr [rax + 7]
    cmp ecx, 2                      # Name.num
    je .Lnumeric_component
    cmp ecx, 1                      # Name.str
    jne .Lbad_cache

    mov rcx, [r15 + 8]
    cmp rcx, -1
    je .Lnext_candidate
    mov rax, [rax + 16]
    mov r10d, 32
    call .Lpointer
    test rax, rax
    jz .Lbad_cache
    cmp byte ptr [rax + 7], 249      # LeanString
    jne .Lbad_cache
    mov rdx, [rax + 8]
    test rdx, rdx
    jz .Lbad_cache
    mov rcx, [r15 + 8]
    lea r8, [rcx + 1]               # Lean size includes the trailing NUL
    cmp rdx, r8
    jne .Lnext_candidate
    lea rdi, [rax + 32]
    mov r9, [r12 + VIEW_MAPPING]
    add r9, [r12 + VIEW_SIZE]
    sub r9, rdi
    cmp rdx, r9
    ja .Lbad_cache
    cmp byte ptr [rdi + rcx], 0
    jne .Lbad_cache
    test rcx, rcx
    jz .Lcomponent_match
    mov rsi, [r15]
    repe cmpsb
    jne .Lnext_candidate
    jmp .Lcomponent_match

.Lnumeric_component:
    cmp qword ptr [r15 + 8], -1
    jne .Lnext_candidate
    mov rcx, [r15]
    cmp rcx, [rax + 16]
    jne .Lnext_candidate
.Lcomponent_match:
    cmp r15, [rsp + LOOKUP_FIRST]
    je .Lprefix_end
    sub r15, NAME_COMPONENT_BYTES
    jmp .Lcomponent
.Lprefix_end:
    cmp rbp, 1
    je .Lfound

.Lnext_candidate:
    mov rax, [rsp + LOOKUP_INDEX]
    test rax, rax
    jz .Lnext_linear
    mov rax, [rax + INDEX_LINKS]
    mov ebx, [rax + rbx*4]
    jmp .Lindexed_candidate
.Lnext_linear:
    inc rbx
    jmp .Lcandidate

.Lfound:
    mov rdi, r12
    mov rsi, rbx
    mov rdx, r13
    call mathlib_olean_record
    jmp .Llookup_done
.Lmissing:
    xor eax, eax
    jmp .Llookup_done
.Lbad_query:
    mov eax, -1
    jmp .Llookup_done
.Lbad_cache:
    mov eax, -2
.Llookup_done:
    add rsp, NAME_STACK_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.size mathlib_olean_lookup_cached, . - mathlib_olean_lookup_cached

# Read the ConstantInfo at a known index. Lookup and catalog construction
# use the same theorem name, type and proof checks. Return 1 or -2.
.globl mathlib_olean_record
.hidden mathlib_olean_record
.type mathlib_olean_record,@function
mathlib_olean_record:
    sub rsp, 8
    cmp rsi, [rdi + VIEW_COUNT]
    jae .Lbad_record
    mov r8, rdx
    mov rax, [rdi + VIEW_CONSTANTS]
    mov rax, [rax + rsi * 8]
    mov r10d, 16
    call .Lpointer
    test rax, rax
    jz .Lbad_record
    cmp byte ptr [rax + 6], 1
    jne .Lbad_record
    movzx ecx, byte ptr [rax + 7]
    cmp ecx, 7
    ja .Lbad_record
    mov [r8 + RESULT_KIND], rcx
    mov rdx, rax
    sub rdx, [rdi + VIEW_MAPPING]
    mov [r8 + RESULT_RECORD], rdx
    mov qword ptr [r8 + RESULT_TYPE], 0
    mov qword ptr [r8 + RESULT_PROOF], 0
    cmp ecx, 2                      # ConstantInfo.thmInfo
    jne .Lvalid_record

    mov rax, [rax + 8]
    mov r10d, 32
    call .Lpointer
    test rax, rax
    jz .Lbad_record
    cmp word ptr [rax + 6], 0x0003   # TheoremVal
    jne .Lbad_record
    mov r9, rax
    mov rax, [rax + 8]
    call .Lpointer                  # ConstantVal is also 32 bytes
    test rax, rax
    jz .Lbad_record
    cmp word ptr [rax + 6], 0x0003
    jne .Lbad_record
    mov rdx, [rdi + VIEW_NAMES]
    mov rdx, [rdx + rsi * 8]
    cmp rdx, [rax + 8]
    jne .Lbad_record
    mov rax, [rax + 24]
    call .Lexpr_offset
    test rax, rax
    jz .Lbad_record
    mov [r8 + RESULT_TYPE], rax
    mov rax, [r9 + 16]
    call .Lexpr_offset
    test rax, rax
    jz .Lbad_record
    mov [r8 + RESULT_PROOF], rax
.Lvalid_record:
    mov eax, 1
    jmp .Lrecord_done
.Lbad_record:
    mov eax, -2
.Lrecord_done:
    add rsp, 8
    ret
.size mathlib_olean_record, .-mathlib_olean_record

.Lexpr_offset:
    sub rsp, 8
    mov r10d, 8
    call .Lpointer
    add rsp, 8
    test rax, rax
    jz .Lbad_pointer
    cmp byte ptr [rax + 7], 11       # Lean.Expr constructor range
    ja .Lbad_pointer
    sub rax, [rdi + VIEW_MAPPING]
    ret

# Split once so the same components can be reused for every declaration.
# rdi = text, rsi = array of { data/boxed Nat, length/-1 }; eax = count/0.
.globl mathlib_olean_parse_query
.hidden mathlib_olean_parse_query
.type mathlib_olean_parse_query,@function
mathlib_olean_parse_query:
    mov r9, rdi
    xor r10d, r10d
.Lstart_part:
    cmp r10d, NAME_COMPONENT_LIMIT
    jae .Linvalid_name
    cmp byte ptr [r9], 0
    je .Linvalid_name
    cmp byte ptr [r9], 0xc2
    jne .Lplain_part
    cmp byte ptr [r9 + 1], 0xab     # U+00AB, opening identifier escape
    jne .Lplain_part
    add r9, 2
    mov r8, r9
.Lquoted_byte:
    movzx eax, byte ptr [r9]
    cmp al, 0x20
    jb .Linvalid_name
    cmp al, 0xc2
    jne .Lquoted_next
    cmp byte ptr [r9 + 1], 0xbb
    je .Lquoted_end
.Lquoted_next:
    inc r9
    jmp .Lquoted_byte
.Lquoted_end:
    mov rdx, r9
    sub rdx, r8
    add r9, 2
    jmp .Lpart_store

.Lplain_part:
    mov r8, r9
.Lplain_byte:
    movzx eax, byte ptr [r9]
    test al, al
    jz .Lplain_end
    cmp al, '.'
    je .Lplain_end
    cmp al, 0x20
    jbe .Linvalid_name
    cmp al, 0x7f
    je .Linvalid_name
    cmp al, 0xc2
    jne .Lplain_next
    cmp byte ptr [r9 + 1], 0xab
    je .Linvalid_name
    cmp byte ptr [r9 + 1], 0xbb
    je .Linvalid_name
.Lplain_next:
    inc r9
    jmp .Lplain_byte
.Lplain_end:
    mov rdx, r9
    sub rdx, r8
    jz .Linvalid_name
    mov r11, r8
.Ldigit_check:
    movzx eax, byte ptr [r11]
    sub eax, '0'
    cmp eax, 9
    ja .Lpart_store
    inc r11
    cmp r11, r9
    jb .Ldigit_check
    xor ecx, ecx
    mov r11, r8
.Lread_nat:
    movzx eax, byte ptr [r11]
    sub eax, '0'
    imul rcx, 10
    jo .Linvalid_name
    add rcx, rax
    jo .Linvalid_name
    inc r11
    cmp r11, r9
    jb .Lread_nat
    lea r8, [rcx + rcx + 1]         # Immediate Lean Nat
    mov rdx, -1

.Lpart_store:
    mov [rsi], r8
    mov [rsi + 8], rdx
    inc r10d
    add rsi, NAME_COMPONENT_BYTES
    movzx eax, byte ptr [r9]
    test al, al
    jz .Lparts_done
    cmp al, '.'
    jne .Linvalid_name
    inc r9
    jmp .Lstart_part
.Lparts_done:
    mov eax, r10d
    ret
.Linvalid_name:
    xor eax, eax
    ret

.size mathlib_olean_parse_query, .-mathlib_olean_parse_query

.section .note.GNU-stack,"",@progbits
