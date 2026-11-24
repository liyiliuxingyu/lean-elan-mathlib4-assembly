.intel_syntax noprefix
.include "proof_format.inc"

.section .rodata
.balign 4
.globl mathlib_nat_succ_injective
.type mathlib_nat_succ_injective, @object
# Mathlib/Data/Nat/Basic.lean at c44e0c8ee63ca166450922a373c7409c5d26b00b.
# Nat.succ_injective, unfolded: for all x,y : Nat, succ x = succ y -> x = y.
mathlib_nat_succ_injective:
    .long 2
    .long 1 + ML_SUCC_STEP, 2 + ML_SUCC_STEP
    .long 1, 2
    .byte ML_ASSUME, ML_CONGR_PRED
.globl mathlib_nat_succ_injective_end
mathlib_nat_succ_injective_end:
.size mathlib_nat_succ_injective, .-mathlib_nat_succ_injective

.section .note.GNU-stack,"",@progbits
