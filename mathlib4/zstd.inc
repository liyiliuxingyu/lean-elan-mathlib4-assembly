# SPDX-License-Identifier: Apache-2.0
# asm_zstd_inspect() writes these unsigned 64-bit fields on success.
.equ ZSTD_CONSUMED, 0
.equ ZSTD_HEADER_BYTES, 8
.equ ZSTD_DICT_ID, 16
.equ ZSTD_WINDOW, 24
.equ ZSTD_CONTENT_SIZE, 32
.equ ZSTD_FLAGS, 40
.equ ZSTD_RAW_COUNT, 48
.equ ZSTD_RLE_COUNT, 56
.equ ZSTD_COMPRESSED_COUNT, 64
.equ ZSTD_KNOWN_BLOCK_BYTES, 72
.equ ZSTD_INFO_BYTES, 80
.equ ZSTD_HAS_CONTENT_SIZE, 1
.equ ZSTD_HAS_CHECKSUM, 2
.equ ZSTD_SINGLE_SEGMENT, 4

.equ ZSTD_OK, 0
.equ ZSTD_INVALID, 1
.equ ZSTD_DICTIONARY, 2
.equ ZSTD_RESERVED, 3
.equ ZSTD_CAPACITY, 4
.equ ZSTD_CHECKSUM, 5
.equ ZSTD_ALLOC, 6

# asm_zstd_next_block() returns one directory entry, all fields u64.
.equ ZSTD_BLOCK_PAYLOAD, 0
.equ ZSTD_BLOCK_STORED, 8
.equ ZSTD_BLOCK_SIZE, 16
.equ ZSTD_BLOCK_TYPE, 24
.equ ZSTD_BLOCK_LAST, 32
.equ ZSTD_BLOCK_INFO_BYTES, 40
