# SPDX-License-Identifier: Apache-2.0
# Included within olean_term.s. These labels share the graph queue, bounded
# row formatter and error exits of mathlib_olean_dump_term. Kinds 4..10
# represent Syntax, SourceInfo, two lists, Substring, String, and Array Syntax.

.pushsection .rodata
.Lsyn_syntax:       .asciz "syntax"
.Lsyn_node:         .asciz "node"
.Lsyn_atom:         .asciz "atom"
.Lsyn_ident:        .asciz "ident"
.Lsyn_source:       .asciz "sourceInfo"
.Lsyn_original:     .asciz "original"
.Lsyn_synthetic:    .asciz "synthetic"
.Lsyn_none:         .asciz "none"
.Lsyn_substring:    .asciz "substring"
.Lsyn_preresolved:  .asciz "preresolved"
.Lsyn_namespace:    .asciz "namespace"
.Lsyn_decl:         .asciz "decl"
.Lsyn_fields:       .asciz "syntaxFields"
.Lsyn_array:        .asciz "syntaxArray"
.Lsyn_arg:          .asciz "syntaxArg"
.Lsyn_text:         .asciz "syntaxText"
.Lsyn_text_chunk:   .asciz "syntaxTextChunk"
.Lsyn_hex:          .ascii "0123456789abcdef"
.popsection

# Fail at the graph's outer stack depth. Helpers using these macros must
# be entered by branches. rbx and rbp survive the shared formatter calls.
.macro SYN_OBJECT bytes
    mov rax, r14
    mov edx, \bytes
    call .Loffset_object
    test rax, rax
    jz .Lbad
    mov rbx, rax
.endm

.macro SYN_CTOR bytes, tagfields
    SYN_OBJECT \bytes
    cmp word ptr [rbx + 4], \bytes
    jne .Lbad
    cmp word ptr [rbx + 6], \tagfields
    jne .Lbad
.endm

.macro SYN_START label
    mov rax, r14
    lea rsi, [rip + \label]
    call .Lrow_header
.endm
.macro SYN_TAG label
    call .Ltab
    lea rsi, [rip + \label]
    call .Ltext
.endm

# Reject forward boxed children even inside a list entry inlined in its
# containing row. The type-specific decoder validates the remaining layout.
.macro SYN_PRIOR container
    test sil, 1
    jnz .Lsyn_prior_done\@
    mov rax, rsi
    sub rax, [r12 + VIEW_BASE]
    jc .Lbad
    mov rcx, \container
    sub rcx, [r12 + VIEW_MAPPING]
    cmp rax, rcx
    jae .Lbad
.Lsyn_prior_done\@:
.endm

.macro SYN_REF container, displacement, kind, allow_nil=0
    call .Ltab
    mov rsi, [\container + \displacement]
    .if !\allow_nil
        test sil, 1
        jnz .Lbad
    .endif
    SYN_PRIOR \container
    mov ecx, \kind
    call .Lreference
    jc .Lbad
.endm
.macro SYN_FORMAT container, displacement, formatter
    call .Ltab
    mov rsi, [\container + \displacement]
    SYN_PRIOR \container
    call .Lformat_args
    call \formatter
    test eax, eax
    js .Lbad
    add r15, rax
.endm

.macro SYN_SOURCE
    cmp qword ptr [rbx + 8], 5      # boxed SourceInfo.none = (2 << 1) | 1
    jne .Lsyn_source_ref\@
    SYN_TAG .Lsyn_none
    jmp .Lsyn_source_done\@
.Lsyn_source_ref\@:
    SYN_REF rbx, 8, NODE_SOURCE_INFO
.Lsyn_source_done\@:
.endm

.Lsyntax_node:
    SYN_OBJECT 8
    cmp byte ptr [rbx + 7], 1
    je .Lsyn_node_ctor
    cmp byte ptr [rbx + 7], 2
    je .Lsyn_atom_ctor
    SYN_CTOR 40, 0x0304            # Syntax.ident
    SYN_START .Lsyn_syntax
    SYN_TAG .Lsyn_ident
    SYN_SOURCE
    SYN_REF rbx, 16, NODE_SUBSTRING
    SYN_FORMAT rbx, 24, mathlib_olean_name_format
    SYN_REF rbx, 32, NODE_PRERESOLVED, 1
    jmp .Lemit
.Lsyn_node_ctor:
    SYN_CTOR 32, 0x0103
    SYN_START .Lsyn_syntax
    SYN_TAG .Lsyn_node
    SYN_SOURCE
    SYN_FORMAT rbx, 16, mathlib_olean_name_format
    SYN_REF rbx, 24, NODE_SYNTAX_ARRAY
    jmp .Lemit
.Lsyn_atom_ctor:
    SYN_CTOR 24, 0x0202
    SYN_START .Lsyn_syntax
    SYN_TAG .Lsyn_atom
    SYN_SOURCE
    SYN_REF rbx, 16, NODE_STRING
    jmp .Lemit

.Lsource_info_node:
    SYN_OBJECT 8
    cmp byte ptr [rbx + 7], 1
    je .Lsyn_synthetic_ctor
    SYN_CTOR 40, 0x0004
    SYN_START .Lsyn_source
    SYN_TAG .Lsyn_original
    SYN_REF rbx, 8, NODE_SUBSTRING
    SYN_FORMAT rbx, 16, mathlib_olean_nat_format
    SYN_REF rbx, 24, NODE_SUBSTRING
    SYN_FORMAT rbx, 32, mathlib_olean_nat_format
    jmp .Lemit
.Lsyn_synthetic_ctor:
    SYN_CTOR 32, 0x0102
    SYN_START .Lsyn_source
    SYN_TAG .Lsyn_synthetic
    SYN_FORMAT rbx, 8, mathlib_olean_nat_format
    SYN_FORMAT rbx, 16, mathlib_olean_nat_format
    call .Ltab
    movzx eax, byte ptr [rbx + 24]
    cmp eax, 1
    ja .Lbad
    call .Lnumber
    jmp .Lemit

.Lsubstring_node:
    SYN_CTOR 32, 0x0003
    SYN_START .Lsyn_substring
    SYN_REF rbx, 8, NODE_STRING
    SYN_FORMAT rbx, 16, mathlib_olean_nat_format
    SYN_FORMAT rbx, 24, mathlib_olean_nat_format
    jmp .Lemit

.Lpreresolved_node:
    SYN_CTOR 24, 0x0102            # List.cons head tail
    mov rdi, r12
    mov rsi, [rbx + 8]
    SYN_PRIOR rbx
    mov edx, 16
    call mathlib_olean_object
    test rax, rax
    jz .Lbad
    mov rbp, rax
    SYN_START .Lsyn_preresolved
    cmp word ptr [rbp + 6], 0x0102
    je .Lsyn_preresolved_decl
    cmp word ptr [rbp + 6], 0x0001
    jne .Lbad
    cmp word ptr [rbp + 4], 16
    jne .Lbad
    SYN_TAG .Lsyn_namespace
    SYN_FORMAT rbp, 8, mathlib_olean_name_format
    jmp .Lsyn_preresolved_tail
.Lsyn_preresolved_decl:
    mov rdi, r12
    mov rsi, [rbx + 8]
    mov edx, 24
    call mathlib_olean_object
    test rax, rax
    jz .Lbad
    cmp word ptr [rbp + 4], 24
    jne .Lbad
    SYN_TAG .Lsyn_decl
    SYN_FORMAT rbp, 8, mathlib_olean_name_format
    SYN_REF rbp, 16, NODE_SYNTAX_FIELDS, 1
.Lsyn_preresolved_tail:
    SYN_REF rbx, 16, NODE_PRERESOLVED, 1
    jmp .Lemit

.Lsyntax_fields_node:                       # List String, Syntax.Preresolved.decl.fields
    SYN_CTOR 24, 0x0102
    SYN_START .Lsyn_fields
    SYN_TAG .Lcons
    SYN_REF rbx, 8, NODE_STRING
    SYN_REF rbx, 16, NODE_SYNTAX_FIELDS, 1
    jmp .Lemit

.Lsyntax_array_node:
    SYN_OBJECT 24
    cmp word ptr [rbx + 6], 0xf600
    jne .Lbad
    mov rdx, [rbx + 8]
    cmp rdx, [rbx + 16]            # the compactor writes exact capacity
    jne .Lbad
    mov rax, [r12 + VIEW_SIZE]
    sub rax, 24                    # SYN_OBJECT already checked room for header
    shr rax, 3
    cmp rdx, rax
    ja .Lbad
    lea rdx, [rdx * 8 + 24]
    mov rax, r14
    call .Loffset_object
    test rax, rax
    jz .Lbad
    SYN_START .Lsyn_array
    call .Ltab
    mov rax, [rbx + 8]
    call .Lnumber
    call .Lwrite_row
    jc .Loutput
    xor ebp, ebp
.Lsyn_array_loop:
    cmp rbp, [rbx + 8]
    jae .Lnext_node
    SYN_START .Lsyn_arg
    call .Ltab
    mov rax, rbp
    call .Lnumber
    call .Ltab
    mov rsi, [rbx + rbp * 8 + 24]
    mov ecx, NODE_SYNTAX           # boxed Syntax.missing is emitted as 0
    call .Lreference
    jc .Lbad
    call .Lwrite_row
    jc .Loutput
    inc rbp
    jmp .Lsyn_array_loop

# Unlike a literal field, the backing string of a Substring can contain the
# entire source file. Emit bounded chunks preserving every byte. Escaping
# non-ASCII bytes keeps each line valid UTF-8 across chunk boundaries.
.Lsyntax_string_node:
    SYN_OBJECT 32
    cmp word ptr [rbx + 6], 0xf900
    jne .Lbad
    mov rbp, [rbx + 8]
    cmp rbp, [rbx + 16]
    jne .Lbad
    test rbp, rbp
    jz .Lbad
    mov rdx, rbp
    add rdx, 32
    jc .Lbad
    mov rax, r14
    call .Loffset_object
    test rax, rax
    jz .Lbad
    dec rbp                         # exclude final NUL from length and content
    cmp byte ptr [rbx + rbp + 32], 0
    jne .Lbad
    SYN_START .Lsyn_text
    call .Ltab
    mov rax, rbp
    call .Lnumber
    call .Lwrite_row
    jc .Loutput
    mov qword ptr [r13 + W_LEVEL], 0
.Lsyn_text_next:
    mov rax, [r13 + W_LEVEL]
    cmp rax, rbp
    jae .Lnext_node
    SYN_START .Lsyn_text_chunk
    call .Ltab
    mov rax, [r13 + W_LEVEL]
    call .Lnumber
    call .Ltab
    mov byte ptr [r15], '"'
    inc r15
    mov r8, [r13 + W_LEVEL]
    mov rcx, rbp
    sub rcx, r8
    cmp rcx, 1024
    jbe .Lsyn_text_have_count
    mov ecx, 1024
.Lsyn_text_have_count:
    lea r9, [rip + .Lsyn_hex]
    add [r13 + W_LEVEL], rcx
.Lsyn_text_byte:
    movzx eax, byte ptr [rbx + r8 + 32]
    cmp al, 32
    jb .Lsyn_text_escape
    cmp al, 127
    jae .Lsyn_text_escape
    cmp al, '"'
    je .Lsyn_text_escape
    cmp al, 92
    je .Lsyn_text_escape
    mov [r15], al
    inc r15
    jmp .Lsyn_text_advance
.Lsyn_text_escape:
    mov word ptr [r15], 0x785c     # \x
    mov edx, eax
    shr eax, 4
    and edx, 15
    mov al, [r9 + rax]
    mov dl, [r9 + rdx]
    mov [r15 + 2], al
    mov [r15 + 3], dl
    add r15, 4
.Lsyn_text_advance:
    inc r8
    dec rcx
    jnz .Lsyn_text_byte
    mov byte ptr [r15], '"'
    inc r15
    call .Lwrite_row
    jc .Loutput
    jmp .Lsyn_text_next
