# SPDX-License-Identifier: Apache-2.0
# Deterministic test caches for the Lean 4.19.0 import reader.
# Extract each .graph_* section with objcopy -O binary -j.
.intel_syntax noprefix

.macro graph_pointer id, target
    .quad .Lgraph_base_\id + (\target - .Lgraph_start_\id)
.endm

.macro graph_header tag, fields, size
    .long 0
    .word \size
    .byte \fields, \tag
.endm

.macro graph_string label, text
    .balign 8
\label:
    graph_header 249, 0, 1
    .quad \label\()_end - \label\()_data
    .quad \label\()_end - \label\()_data
    .quad \label\()_end - \label\()_data - 1
\label\()_data:
    .asciz "\text"
\label\()_end:
.endm

.macro graph_name id, label, text, prefix
    .balign 8
\label:
    graph_header 1, 2, 32
    .ifb \prefix
        .quad 1
    .else
        graph_pointer \id, \prefix
    .endif
    graph_pointer \id, \text
    .quad 0                        # The path reader does not use Name.hash.
.endm

.macro graph_import id, module, runtime=0
    .balign 8
.Limport_\id\()_\module:
    graph_header 0, 1, 24
    graph_pointer \id, .Limport_name_\id\()_\module
    .byte \runtime
    .zero 7

    graph_string .Limport_text_\id\()_\module, \module
    graph_name \id, .Limport_name_\id\()_\module, .Limport_text_\id\()_\module, .Lpackage_\id
.endm

.macro graph_image section, decl, count, dep0, dep1, runtime, theorem=0
    .section \section,"a",@progbits
    .balign 8
    .equ .Lgraph_base_\@, 0x1234000000 + 65536 * \@
.Lgraph_start_\@:
    .ascii "olean"
    .byte 2, 1
    .ascii "4.19.0"
    .zero 27
    .ascii "6caaee842e9495688c1567e78c0e68dbb96942aa"
    .quad .Lgraph_base_\@
    graph_pointer \@, .Lmodule_\@

.Lmodule_\@:
    graph_header 0, 5, 48
    graph_pointer \@, .Limports_\@
    graph_pointer \@, .Lnames_\@
    graph_pointer \@, .Lconstants_\@
    graph_pointer \@, .Lempty_\@
    graph_pointer \@, .Lempty_\@

.Limports_\@:
    graph_header 246, 0, 1
    .quad \count, \count
    .ifnb \dep0
        graph_pointer \@, .Limport_\@\()_\dep0
    .endif
    .ifnb \dep1
        graph_pointer \@, .Limport_\@\()_\dep1
    .endif
    .ifnb \runtime
        graph_pointer \@, .Limport_\@\()_\runtime
    .endif

.Lempty_\@:
    graph_header 246, 0, 1
    .quad 0, 0

.Lnames_\@:
    graph_header 246, 0, 1
    .quad 1, 1
    graph_pointer \@, .Ldeclaration_\@

.Lconstants_\@:
    graph_header 246, 0, 1
    .quad 1, 1
    graph_pointer \@, .Lconstant_info_\@

.Lconstant_info_\@:
    .if \theorem
        graph_header 2, 1, 16      # ConstantInfo.thmInfo
        graph_pointer \@, .Ltheorem_val_\@
.Ltheorem_val_\@:
        graph_header 0, 3, 32
        graph_pointer \@, .Lconstant_val_\@
        graph_pointer \@, .Lproof_\@
        .quad 1                    # Empty mutual declaration list
    .else
        graph_header 0, 1, 16
        graph_pointer \@, .Laxiom_val_\@
.Laxiom_val_\@:
        graph_header 0, 1, 24
        graph_pointer \@, .Lconstant_val_\@
        .quad 0                    # isUnsafe = false with padding
    .endif
.Lconstant_val_\@:
    graph_header 0, 3, 32
    graph_pointer \@, .Ldeclaration_\@
    .quad 1                        # Empty universe parameter list
    graph_pointer \@, .Ltype_\@
.Ltype_\@:
    .if \theorem
        graph_header 4, 2, 32      # Expr.const True []
        graph_pointer \@, .Ltrue_name_\@
        .quad 1, 0
.Lproof_\@:
        .if \theorem == 2
            graph_header 5, 2, 32  # Invalid Expr.app with a self-edge.
            graph_pointer \@, .Lproof_\@
            graph_pointer \@, .Ltype_\@
            .quad 0
        .else
            graph_header 4, 2, 32  # Expr.const True.intro []
            graph_pointer \@, .Lintro_name_\@
            .quad 1, 0
        .endif
        graph_string .Ltrue_text_\@, True
        graph_name \@, .Ltrue_name_\@, .Ltrue_text_\@
        graph_string .Lintro_text_\@, intro
        graph_name \@, .Lintro_name_\@, .Lintro_text_\@, .Ltrue_name_\@
    .else
        graph_header 3, 1, 24      # Expr.sort Level.zero
        .quad 1, 0
    .endif

    graph_string .Ldecl_text_\@, \decl
    graph_name \@, .Ldeclaration_\@, .Ldecl_text_\@
    .if \count
        graph_string .Lpackage_text_\@, CacheTest
        graph_name \@, .Lpackage_\@, .Lpackage_text_\@
    .endif
    .ifnb \dep0
        graph_import \@, \dep0
    .endif
    .ifnb \dep1
        graph_import \@, \dep1
    .endif
    .ifnb \runtime
        graph_import \@, \runtime, 1
    .endif
.endm

graph_image .graph_root, cacheTestRoot, 3, Left, Right, UnavailableRuntime
graph_image .graph_left, cacheTestLeft, 1, Leaf
graph_image .graph_right, cacheTestRight, 1, Leaf
graph_image .graph_leaf, cacheTestLeaf, 0
graph_image .graph_term, cacheTestTerm, 0, , , , 1
graph_image .graph_term_cycle, cacheTestTermCycle, 0, , , , 2

.section .note.GNU-stack,"",@progbits
