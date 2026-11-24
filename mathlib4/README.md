# `Nat.succ_injective` 汇编证明证书

mathlib4 `v4.19.0` 的 `Nat.succ_injective` 断言，对任意自然数 `x` 和 `y`，由 `Nat.succ x = Nat.succ y` 得到 `x = y`。原声明调用 Lean 核心的 `Nat.succ.inj`。这里把同一命题编码成汇编数据，通过给等式两边应用 `Nat.pred` 推导结论。[上游声明](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Mathlib/Data/Nat/Basic.lean#L55)

`verify.s` 检查独立的等式证书格式，`nat_succ_injective.s` 提供所用证书。证书记录量化变量个数、假设等式两端、目标等式两端，然后逐字节记录证明步骤。检查器先取用假设等式，再通过对称性或对两端应用相同的 `succ` 或 `pred` 得到新等式，最后逐项比较等式两端与目标。

## 数据格式

头部为五个小端 32 位字段，顺序以 `proof_format.inc` 为准。一个自然数项采用 `succ^p(pred^q(x))`，其中 `x` 由最低 8 位编码，`p` 和 `q` 分别由后续两个 12 位字段编码。编号零表示常量 `0` 且要求 `q = 0`，其余编号对应自然数量化变量。项编码的位宽限制表达式可写出的后继和前驱层数，量化变量的取值域仍是全体自然数。

| 字节 | 规则 | 对当前等式 `a = b` 的作用 |
|---|---|---|
| `01` | 引入假设 | 读取头部中的假设等式，须为首个字节 |
| `02` | 前驱同余 | 得到 `pred(a) = pred(b)` |
| `03` | 后继同余 | 得到 `succ(a) = succ(b)` |
| `04` | 等式对称 | 得到 `b = a` |

应用 `pred` 时，若 `p > 0`，由 `pred(succ(t)) = t` 把 `p` 减一。若 `p = 0` 且 `x` 是变量，把 `q` 加一。若该项为零，由 `pred(0) = 0` 保持零。应用 `succ` 把 `p` 加一。无法放入 12 位字段的中间项会被拒绝。`Nat.succ_injective` 的证书使用 `01 02`，把两端的 `p` 都从一减到零。

## 编译与验证

目标为 x86-64 Linux，依赖 GNU `as`、GNU `ld` 与 `make`。受测的 SysV 函数 `mathlib_verify_nat_certificate` 通过 `rdi` 和 `rsi` 接收可读缓冲区和字节数，接受时在 `eax` 返回 `1`，拒绝时返回 `0`。

```sh
make -C mathlib4 test
make -C mathlib4 test-lean LEAN=/path/to/lean
```

第一条命令运行 16 个汇编测试，覆盖有效证书、交换等式、边界、非法编码和错误目标。第二条命令先用 `export_lean.s` 汇编出的程序核对证书，再根据它的步骤生成 Lean 证明项并调用 Lean 检验。已用 Lean `v4.19.0` 验证生成的声明。这里的检查器只覆盖上述自然数等式格式，Lean 核心仍用于独立复核导出的证明项。
