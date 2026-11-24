# SPDX-License-Identifier: Apache-2.0
# Linux x86-64 view and result ABI for the Lean 4.19.0 cache reader.
.equ VIEW_MAPPING, 0
.equ VIEW_SIZE, 8
.equ VIEW_BASE, 16
.equ VIEW_NAMES, 24
.equ VIEW_CONSTANTS, 32
.equ VIEW_COUNT, 40
.equ VIEW_IMPORTS, 48
.equ VIEW_IMPORT_DATA, 56
.equ VIEW_BYTES, 64
.equ RESULT_KIND, 0
.equ RESULT_RECORD, 8
.equ RESULT_TYPE, 16
.equ RESULT_PROOF, 24
.equ RESULT_BYTES, 32

# Ephemeral per-module index. Buckets and links contain one-based array indices.
.equ INDEX_SIZE, 0
.equ INDEX_MASK, 8
.equ INDEX_LINKS, 16
.equ INDEX_HEADS, 24

# Count followed by up to 64 pairs {component pointer or boxed Nat, length}.
.equ QUERY_COMPONENTS, 8
.equ QUERY_BYTES, QUERY_COMPONENTS + 64 * 16
