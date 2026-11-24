# SPDX-License-Identifier: Apache-2.0
# All disk fields are little-endian u64. Header, modules, declarations,
# open-addressed slots and the byte pool are consecutive, without padding.
.equ CAT_MAGIC, 0x3130305441434c4d   # "MLCAT001"
.equ H_SIZE, 8
.equ H_MODULES, 16
.equ H_RECORDS, 24
.equ H_SLOTS, 32
.equ H_POOL, 40
.equ H_SKIPPED, 48                  # names outside the supported query grammar
.equ H_BYTES, 64                    # final word reserved, zero
.equ M_PATH, 0                      # pool-relative, absolute NUL-ended pathname
.equ M_SIGNATURE, 8                 # XXH64 of original archive
.equ M_BYTES, 16
.equ R_HASH, 0                      # XXH64 of complete canonical Name key
.equ R_KEY, 8                       # pool-relative offset
.equ R_LENGTH, 16
.equ R_MODULE, 24                   # zero-based index
.equ R_KIND, 32
.equ R_BYTES, 40
.equ V_HEADER, 0                    # in-memory view, pointers only
.equ V_MODULES, 8
.equ V_RECORDS, 16
.equ V_SLOTS, 24
.equ V_POOL, 32
.equ V_BYTES, 40
.equ A_DATA, 0                      # growing anonymous mapping
.equ A_USED, 8
.equ A_CAP, 16
.equ A_BYTES, 24
