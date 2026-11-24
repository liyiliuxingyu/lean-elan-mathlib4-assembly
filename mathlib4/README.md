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

该命令返回 `theorem` 和 `Nat.succ_injective`，两者用制表符分隔。给出多个声明名时依次返回结果。不带声明名时显示当前模块的声明数和直接导入数。状态码 `0` 表示成功，`1` 表示至少一个声明在当前模块中缺失，`2` 表示参数、输入缓存或 I/O 出错。声明名区分大小写，支持点分隔、`«…»` 转义和 63 位非负数字分量，最多 64 个分量。默认模式只查当前文件的声明表。

如需获取缓存，在上游 mathlib4 `v4.19.0` 仓库中使用对应 Lean 工具链运行下列命令。解包后的目标位于 `.lake/build/lib/lean/Mathlib/Data/Nat/Basic.olean`。[上游缓存命令](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Cache/Main.lean)

```sh
lake exe cache get Mathlib/Data/Nat/Basic.lean
```

`olean_read.s` 提供 SysV 接口 `mathlib_olean_parse(buf, size, view)` 和 `mathlib_olean_lookup(view, name, result)`。地址、计数和返回结构见 `olean_layout.inc`。`parse` 返回 `1` 或 `0`。`lookup` 返回 `1`、`0`、`-1` 或 `-2`，分别对应命中、缺失、名称格式错误和访问到的缓存结构损坏。命中时返回记录偏移和声明种类，定理另返回类型与证明根节点的文件偏移。该接口读取已访问的记录，完整对象图的加载、内核证明检查以及缓存写入仍由上游工具处理。调用期间应保持缓存文件内容稳定。

`make -C mathlib4 test-cache` 运行独立的汇编测试，覆盖格式检查、数组边界、精确名称匹配及类型和证明根偏移。真实缓存和性能核验记录见根目录说明。

## 沿导入关系查询

在上游 Mathlib4 v4.19.0 仓库中运行下列命令。把读取器的路径替换为实际构建路径。配套 Lake 会为查询设置包含依赖和 Lean 标准库的 `LEAN_PATH`。

```sh
lake env /path/to/build/mathlib4/mathlib-olean --recursive \
  .lake/build/lib/lean/Mathlib/Data/Nat/Basic.olean \
  Nat.succ_injective Nat.succ Function.Injective Eq.rec
```

`--recursive` 要求至少一个声明名。读取器从指定文件开始，按广度优先遍历普通导入，跳过标为 `runtimeOnly` 的导入。待访问的模块名只入队一次，每次只映射当前模块，全部查询命中后停止。查询结果保持参数顺序。命中为制表符分隔的种类和名称，完成遍历后仍缺失的声明返回 `missing` 和退出状态 `1`。如果查询过程遇到缺失或无法读取的缓存，命令会显示相应路径并返回 `2`。在结果已全部找到时，尚未访问的模块无需读取。

也可直接设置冒号分隔的 `LEAN_PATH`。包根选择遵循 Lean 4.19.0 的规则，搜索路径中第一个包含顶级包目录或该包 `.olean` 的条目决定后续模块的位置，空条目表示当前目录。手动设置时，标准库所在的 `$(lean --print-prefix)/lib/lean` 也应在列表内。查询不会构建 Lean 环境，内核证明检查仍由官方 Lean 完成。[Lean 搜索路径](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Util/Path.lean#L46)

`make -C mathlib4 test-cache` 同时测试单文件数据读取和递归查询。递归测试包含共享叶节点、缺失的仅运行时导入、包路径优先级和提前命中。实现上限为 65,536 个排队模块、16 MiB 模块路径数据和 4,095 字节单路径。当前可读版本为官方 Linux x86-64 Lean 4.19.0 发行版生成的缓存。


## 导出定理类型与证明表达式

`--term` 导出一个当前文件声明的定理。入口遵循 `.olean` 查询的版本约束。表格用制表符分隔，第一行的 `type` 和第二行的 `proof` 给出各自根节点的文件字节偏移。后续每个节点只输出一次，偏移可用来追踪引用关系。

```sh
build/mathlib4/mathlib-olean --term /path/to/Mathlib/Data/Nat/Basic.olean Nat.succ_injective
```

| 记录 | 构造器 | 偏移和构造器后的字段 |
| --- | --- | --- |
| `expr` | `bvar` | de Bruijn 索引 |
| `expr` | `fvar`、`mvar` | 变量名 |
| `expr` | `sort` | 宇宙层级偏移 |
| `expr` | `const` | 常量名、宇宙层级列表偏移 |
| `expr` | `app` | 函数偏移、参数偏移 |
| `expr` | `lam`、`forallE` | 绑定名、类型偏移、主体偏移、绑定方式 |
| `expr` | `letE` | 绑定名、类型偏移、值偏移、主体偏移、非依赖标志 |
| `expr` | `lit` | `nat` 或 `string`、相应字面量 |
| `expr` | `mdata` | 元数据表偏移、表达式偏移 |
| `expr` | `proj` | 结构名、字段索引、被投影表达式偏移 |
| `level` | `succ`、`max`、`imax` | 一个或两个宇宙层级偏移 |
| `level` | `param`、`mvar` | 层级参数或元变量名 |
| `levels` | `cons` | 首项层级偏移、尾部列表偏移 |

宇宙零层级、空宇宙列表和空元数据表各以对应字段中的 `0` 表示。绑定方式依次用 `0`、`1`、`2`、`3` 表示显式、隐式、严格隐式和实例隐式。自然数输出十进制。字符串和名称中的控制字节以 `\xNN` 表示。定理的类型、证明、子表达式和宇宙数据均从映射中读取。元数据表按其文件偏移继续展开，输出键、值、列表尾部和所引用的语法节点。[完整字段及转义规则](TERM-METADATA.md) 内部引用的定理常量保留名称，证明类型检查和常量展开仍由 Lean 负责。[固定版表达式定义](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Expr.lean)

行缓冲区随文件大小增长，长语法文本可以分块输出。找不到当前文件中的定理时返回 `1`，非定理、格式错误、超过行长上限或 I/O 错误返回 `2`。`make -C mathlib4 test-term` 使用随包的汇编缓存夹具检查导出、非法循环引用和标量数据。


## 批量声明查询与压缩包直读

单文件命令和 `--recursive` 的调用格式与第四阶段相同。对于至少 64 条声明、且仍有至少 16 个名称待查的模块，读取器在内存中给名称的最后一级分量建立哈希索引。多个命中同一桶的名称逐分量比较，保留原声明顺序。较小的查询直接扫描。临时索引随模块释放，磁盘缓存文件保持只读。若索引无法建立，读取器回到原有的按需扫描。批量 stdout 输出在 16 KiB 缓冲区中组装，结果仍按输入参数顺序排列。

递归查询从后续查找中移除已命中的参数。最多为 8,192 个查询保留已解析的名称分量，包目录分桶记忆，仍按原 `LEAN_PATH` 优先级选中包根。已选择的包目录和缓存内容应在单次命令期间保持稳定。

已有 `.ltar` 压缩包时，可用 `mathlib-ltar --list FILE.ltar` 列出成员，用 `--lookup FILE.ltar NAME...` 批量查询模块声明，用 `--term FILE.ltar THEOREM` 输出类型与证明。这两个查询均在内存中展开所需成员。[归档成员和注释格式](LTAR.md)
