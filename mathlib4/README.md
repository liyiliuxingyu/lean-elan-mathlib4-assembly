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

## 直接查询 `.olean` 缓存

`mathlib-olean` 在 Linux x86-64 上直接只读映射本地 `.olean`。它把文件里的虚拟地址换算成文件偏移，读取模块声明名和声明记录，用一个映射处理同一模块的多次查询。构建及查询都只需 GNU 汇编工具和 Linux，查询时无需启动 Lean 或 Lake。支持 Lean 4.19.0 官方 Linux x86-64 发行版生成的缓存，文件格式、GMP 标志和 Lean 提交必须匹配。[Lean 的缓存头格式](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/library/module.cpp) · [模块数据定义](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Environment.lean#L125)

已有解包缓存时，从本工程根目录构建并查询。

```sh
make
build/mathlib4/mathlib-olean /path/to/Mathlib/Data/Nat/Basic.olean Nat.succ_injective
```

该命令返回 `theorem` 和 `Nat.succ_injective`，两者用制表符分隔。给出多个声明名时依次返回结果。不带声明名时显示当前模块的声明数和直接导入数。状态码 `0` 表示成功，`1` 表示至少一个声明在当前模块中缺失，`2` 表示参数、输入缓存或 I/O 出错。声明名区分大小写，支持点分隔、`«…»` 转义和 63 位非负数字分量，最多 64 个分量。查询只查当前模块的声明表，导入的声明需查询其所在模块。

如需获取缓存，在上游 mathlib4 `v4.19.0` 仓库中使用对应 Lean 工具链运行下列命令。解包后的目标位于 `.lake/build/lib/lean/Mathlib/Data/Nat/Basic.olean`。[上游缓存命令](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Cache/Main.lean)

```sh
lake exe cache get Mathlib/Data/Nat/Basic.lean
```

`olean_read.s` 提供 SysV 接口 `mathlib_olean_parse(buf, size, view)` 和 `mathlib_olean_lookup(view, name, result)`。地址、计数和返回结构见 `olean_layout.inc`。`parse` 返回 `1` 或 `0`。`lookup` 返回 `1`、`0`、`-1` 或 `-2`，分别对应命中、缺失、名称格式错误和访问到的缓存结构损坏。命中时返回记录偏移和声明种类，定理另返回类型与证明根节点的文件偏移。该接口读取已访问的记录，完整对象图的加载、内核证明检查以及缓存写入仍由上游工具处理。调用期间应保持缓存文件内容稳定。

`make -C mathlib4 test-cache` 运行独立的汇编测试，覆盖格式检查、数组边界、精确名称匹配及类型和证明根偏移。真实缓存和性能核验记录见根目录说明。
