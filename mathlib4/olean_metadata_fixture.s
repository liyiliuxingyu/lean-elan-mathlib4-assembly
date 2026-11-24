# SPDX-License-Identifier: Apache-2.0
# Lean 4.19 .olean with a single theorem and all six DataValue constructors.
# Assemble with --defsym META_FAULT=1 for an invalid Bool, =2 for a cyclic
# metadata list, or =3 for a forward Syntax-array edge. Extract .meta_fixture.
.intel_syntax noprefix
.ifndef META_FAULT
.set META_FAULT, 0
.endif

.section .meta_fixture,"a",@progbits
.balign 8
.Lstart:
.equ cache_base, 0x1200000000
.macro ref target
    .quad cache_base + (\target - .Lstart)
.endm
.macro header tag, fields, bytes
    .long 0
    .word \bytes
    .byte \fields, \tag
.endm
.macro string label, value
\label:
    header 249, 0, 1
    .quad 2f-1f, 2f-1f, 2f-1f-1
1:  .asciz "\value"
2:  .zero (-(2b-1b)) & 7        # constant padding also permits assembly-time offset text
.endm
.macro name label, value, parent
    string .Lchars_\@, \value
\label:
    header 1, 2, 32
    .ifb \parent
        .quad 1
    .else
        ref \parent
    .endif
    ref .Lchars_\@
    .quad 0
.endm
.macro cons label, head, tail
\label:
    header 1, 2, 24
    ref \head
    .ifb \tail
        .quad 1
    .else
        ref \tail
    .endif
.endm
.macro slice label, start, stop
\label:
    header 0, 3, 32
    ref .Lsource_text
    .quad 2*\start+1, 2*\stop+1
.endm
.macro entry label, key, tag, pointer, scalar, tail
    name .Lkey_\@, \key
.Lvalue_\@:
    .if \tag == 1
        header 1, 0, 16
    .else
        header \tag, 1, 16
    .endif
    .ifnb \pointer
        ref \pointer
    .else
        .quad \scalar
    .endif
.Lpair_\@:
    header 0, 2, 24
    ref .Lkey_\@
    ref .Lvalue_\@
    cons \label, .Lpair_\@, \tail
.endm

    .ascii "olean"
    .byte 2, 1
    .ascii "4.19.0"
    .zero 27
    .ascii "6caaee842e9495688c1567e78c0e68dbb96942aa"
    .quad cache_base
    ref .Lmodule

    string .Lsource_text, "  alpha  "
    slice .Lleading, 0, 2
    slice .Lraw_ident, 2, 7
    slice .Ltrailing, 7, 9
.Loriginal:
    header 0, 4, 40
    ref .Lleading
    .quad 5
    ref .Ltrailing
    .quad 15
.Lsynthetic:
    header 1, 2, 32
    .quad 7, 9, 1
    string .Ltoken, "?"
.Latom:
    header 2, 2, 24
    ref .Lsynthetic
    ref .Ltoken
    name .Lnat, Nat
    name .Lsucc, succ, .Lnat
    name .Lprod, Prod
    string .Lfst, fst
    string .Lsnd, snd
    cons .Lsecond_field, .Lsnd
    cons .Lfields, .Lfst, .Lsecond_field
.Lpredecl:
    header 1, 2, 24
    ref .Lprod
    ref .Lfields
.Lprens:
    header 0, 1, 16
    ref .Lnat
    cons .Llast_pre, .Lpredecl
    cons .Lpre, .Lprens, .Llast_pre
    name .Lalpha, alpha
.Lident:
    header 3, 4, 40
    ref .Loriginal
    ref .Lraw_ident
    ref .Lalpha
    ref .Lpre
.Largs:
    header 246, 0, 1
    .quad 4, 4
    ref .Latom
    ref .Lident
    .quad 1
    .if META_FAULT == 3
        ref .Ltree
    .else
        ref .Latom
    .endif
    name .Lgroup, group
.Ltree:
    header 1, 3, 32
    .quad 5                      # SourceInfo.none
    ref .Lgroup
    ref .Largs

.Lpos_mpz:
    header 250, 0, 40
    .long 2, 2
    ref 1f
1:  .quad 2, 1                   # 2^64 + 2
.Lneg_mpz:
    header 250, 0, 40
    .long 2, -2
    ref 2f
2:  .quad 1, 1                   # -(2^64 + 1)
    string .Lmessage, "a\tb"
    entry .Llast, absent, 5, , 1
    entry .Lsyntax, metaSyntax, 5, .Ltree, , .Llast
    entry .Lbigpos, bigPos, 4, .Lpos_mpz, , .Lsyntax
    entry .Lbigneg, bigNeg, 4, .Lneg_mpz, , .Lbigpos
    entry .Lsint, signed, 4, , 0x1ffffffff, .Lbigneg
    entry .Lcount, count, 3, .Lpos_mpz, , .Lsint
    entry .Lnameval, name, 2, .Lsucc, , .Lcount
    .if META_FAULT == 1
        entry .Lbool, flag, 1, , 2, .Lnameval
    .else
        entry .Lbool, flag, 1, , 1, .Lnameval
    .endif
    .if META_FAULT == 2
        entry .Lmetadata, text, 0, .Lmessage, , .Lmetadata
    .else
        entry .Lmetadata, text, 0, .Lmessage, , .Lbool
    .endif
    name .Ltrue, True
    name .Lintro, intro, .Ltrue
.Ltype:
    header 4, 2, 32
    ref .Ltrue
    .quad 1, 0
.Lproof_body:
    header 4, 2, 32
    ref .Lintro
    .quad 1, 0
.Lproof:
    header 10, 2, 32
    ref .Lmetadata
    ref .Lproof_body
    .quad 0
    name .Ldecl_name, cacheMetaFixture
.Lconstant:
    header 0, 3, 32
    ref .Ldecl_name
    .quad 1
    ref .Ltype
.Ltheorem:
    header 0, 3, 32
    ref .Lconstant
    ref .Lproof
    .quad 1
.Linfo:
    header 2, 1, 16
    ref .Ltheorem
.Lempty:
    header 246, 0, 1
    .quad 0, 0
.Lnames:
    header 246, 0, 1
    .quad 1, 1
    ref .Ldecl_name
.Linfos:
    header 246, 0, 1
    .quad 1, 1
    ref .Linfo
.Lmodule:
    header 0, 5, 48
    ref .Lempty
    ref .Lnames
    ref .Linfos
    ref .Lempty
    ref .Lempty

# Expected (key, kind, value) projection, with nonzero syntax IDs replaced
# by @. Linkage between list entries and syntax nodes is checked separately.
.section .meta_expected,"a",@progbits
.ascii "text\tstring\t\"a\\x09b\"\n"
.ascii "flag\tbool\t1\n"
.ascii "name\tname\tNat.succ\n"
.ascii "count\tnat\t18446744073709551618\n"
.ascii "signed\tint\t-1\n"
.ascii "bigNeg\tint\t-18446744073709551617\n"
.ascii "bigPos\tint\t18446744073709551618\n"
.ascii "metaSyntax\tsyntax\t@\n"
.ascii "absent\tsyntax\t0\n"

# Full graph oracle. Label differences are cache offsets calculated by the
# assembler, including the header. Comparing sorted TSV rows checks all
# edges, scalar fields and duplicates without requiring a traversal order.
.section .meta_graph_expected,"a",@progbits
.altmacro
.irp label,type,proof,proof_body,metadata,bool,nameval,count,sint,bigneg,bigpos,syntax,last
    .set id_\label, .L\label - .Lstart
.endr
.irp label,tree,args,atom,ident,synthetic,token,original,leading,trailing,raw_ident,source_text
    .set id_\label, .L\label - .Lstart
.endr
.irp label,pre,last_pre,fields,second_field,fst,snd
    .set id_\label, .L\label - .Lstart
.endr
.macro expected_field val
    .ascii "\t&val"
.endm
.macro expected_prefix kind, owner, f1, f2, f3, f4, f5
    .ascii "&kind"
    expected_field \owner
    .irp val,\f1,\f2,\f3,\f4,\f5
        .ifnb \val
            expected_field \val
        .endif
    .endr
.endm
.macro expected_row kind, owner, f1, f2, f3, f4, f5
    expected_prefix \kind, \owner, \f1, \f2, \f3, \f4, \f5
    .byte 10
.endm

expected_row type, %id_type
expected_row proof, %id_proof
expected_row expr, %id_type, const, True, 0
expected_row expr, %id_proof, mdata, %id_metadata, %id_proof_body
expected_row expr, %id_proof_body, const, True.intro, 0

expected_prefix metadata, %id_metadata, entry, text, string
.ascii "\t\"a\\x09b\""
expected_field %id_bool
.byte 10
expected_row metadata, %id_bool, entry, flag, bool, 1, %id_nameval
expected_row metadata, %id_nameval, entry, name, name, Nat.succ, %id_count
expected_row metadata, %id_count, entry, count, nat, 18446744073709551618, %id_sint
expected_row metadata, %id_sint, entry, signed, int, -1, %id_bigneg
expected_row metadata, %id_bigneg, entry, bigNeg, int, -18446744073709551617, %id_bigpos
expected_row metadata, %id_bigpos, entry, bigPos, int, 18446744073709551618, %id_syntax
expected_row metadata, %id_syntax, entry, metaSyntax, syntax, %id_tree, %id_last
expected_row metadata, %id_last, entry, absent, syntax, 0, 0

expected_row syntax, %id_tree, node, none, group, %id_args
expected_row syntaxArray, %id_args, 4
expected_row syntaxArg, %id_args, 0, %id_atom
expected_row syntaxArg, %id_args, 1, %id_ident
expected_row syntaxArg, %id_args, 2, 0
expected_row syntaxArg, %id_args, 3, %id_atom
expected_row syntax, %id_atom, atom, %id_synthetic, %id_token
expected_row syntax, %id_ident, ident, %id_original, %id_raw_ident, alpha, %id_pre
expected_row sourceInfo, %id_synthetic, synthetic, 3, 4, 1
expected_row sourceInfo, %id_original, original, %id_leading, 2, %id_trailing, 7
expected_row substring, %id_raw_ident, %id_source_text, 2, 7
expected_row substring, %id_leading, %id_source_text, 0, 2
expected_row substring, %id_trailing, %id_source_text, 7, 9

expected_row preresolved, %id_pre, namespace, Nat, %id_last_pre
expected_row preresolved, %id_last_pre, decl, Prod, %id_fields, 0
expected_row syntaxFields, %id_fields, cons, %id_fst, %id_second_field
expected_row syntaxFields, %id_second_field, cons, %id_snd, 0

expected_row syntaxText, %id_source_text, 9
expected_prefix syntaxTextChunk, %id_source_text, 0
.ascii "\t\"  alpha  \"\n"
expected_row syntaxText, %id_token, 1
expected_prefix syntaxTextChunk, %id_token, 0
.ascii "\t\"?\"\n"
expected_row syntaxText, %id_fst, 3
expected_prefix syntaxTextChunk, %id_fst, 0
.ascii "\t\"fst\"\n"
expected_row syntaxText, %id_snd, 3
expected_prefix syntaxTextChunk, %id_snd, 0
.ascii "\t\"snd\"\n"

.noaltmacro
.section .note.GNU-stack,"",@progbits
