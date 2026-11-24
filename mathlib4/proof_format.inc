# A certificate is a 20-byte little-endian header and a chain of opcodes.
.equ ML_VARIABLE_COUNT,     0
.equ ML_HYPOTHESIS_LEFT,    4
.equ ML_HYPOTHESIS_RIGHT,   8
.equ ML_GOAL_LEFT,         12
.equ ML_GOAL_RIGHT,        16
.equ ML_HEADER_SIZE,       20

# A Nat term is succ^p(pred^q(x)), with x = 0 or a bound variable.
.equ ML_VARIABLE_MASK, 0x000000ff
.equ ML_SUCC_MASK,     0x000fff00
.equ ML_PRED_MASK,     0xfff00000
.equ ML_SUCC_STEP,     0x00000100
.equ ML_PRED_STEP,     0x00100000

.equ ML_ASSUME,    1
.equ ML_CONGR_PRED, 2
.equ ML_CONGR_SUCC, 3
.equ ML_SYMMETRY,   4
