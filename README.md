# Lean 4、Elan、Mathlib4 汇编移植

这是三个项目的汇编移植源码。目标是 Linux x86-64、ELF 和 System V AMD64 ABI。实现与自测采用 GNU `as` 的 Intel 汇编语法。Makefile 负责组装、链接和运行测试。

| 项目 | 此版本实现 | 上游基线 |
| --- | --- | --- |
| Lean 4 | `hash_str` 和 `src/runtime/utf8.cpp` 的全部 19 个公开符号，覆盖官方 Linux x86-64 发行版 ABI。 | [v4.19.0 · 6caaee842e94](https://github.com/leanprover/lean4/tree/6caaee842e9495688c1567e78c0e68dbb96942aa/src/runtime) |
| Elan | 解析工具链描述符和目录名，可启动显式选定的本地或已安装工具链中的命令。 | [v4.2.4 · 227caca13372](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-dist/src/dist.rs) |
| Mathlib4 | 将 `Nat.succ_injective` 表示为汇编数据，提供汇编证明检查器和 Lean 证明导出程序。新增独立汇编工具，直接查询编译好的 `.olean` 文件，可沿普通导入遍历模块和导出定理的类型与证明表达式。 | [v4.19.0 · c44e0c8ee63c](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Mathlib/Data/Nat/Basic.lean#L55) |

## 构建与验证

在 Linux x86-64 上安装 GNU Make 和 GNU Binutils 后，从本目录运行。

```sh
make
make test
```

`make` 生成 `build/lean4/liblean-asm-runtime.a`、`build/elan/elan-asm-descriptor`、`build/elan/elan-asm-run`、`build/mathlib4/export-lean` 和 `build/mathlib4/mathlib-olean`。

```sh
build/elan/elan-asm-descriptor parse leanprover/lean4:v4.19.0
build/elan/elan-asm-descriptor dir leanprover--lean4---v4.19.0
build/elan/elan-asm-run /path/to/lean-4.19.0-linux lean --version
build/mathlib4/export-lean
make test-lean LEAN=/path/to/lean
build/mathlib4/mathlib-olean --term /path/to/Mathlib/Data/Nat/Basic.olean Nat.succ_injective
```

`make test` 运行独立的汇编测试。`make test-lean` 需要官方 Lean v4.19.0。它把证明证书转换为 Lean 源码，再由官方 Lean 检查该命题的证明。证书格式、缓存用法、信任范围和 Elan 的接口约定见子目录说明。

## 运行时、启动器和证明表达式核验

- 哈希与固定提交编译出的 C++ 实现逐项比较 18,344 次，覆盖非对齐输入、尾部长度、随机种子和内存页边界。
- UTF-8 的 11 个入口与官方 Lean 4.19.0 发行版直接对照，覆盖全部 256 个单字节分类和 65,536 种双字节输入，以及固定种子的随机用例。
- UTF-8 余下 8 个公开符号通过 36,444 项上游对照。将三个汇编对象合并并替换进官方 `libleanrt.a` 副本后，使用官方 `leanc` 链接的 Unicode 程序运行成功。涉及 `std::string` 和 `std::vector` 的重载仍使用官方发行版的 libc++/libc++abi。仅构建汇编归档与运行 `make test` 无需链接这些库。
- Mathlib4 的 `--term` 与官方 `Lean.readModuleData` 逐节点比较了 `Mathlib.Data.Nat.Basic`、`Mathlib.Data.Nat.Init`、`Mathlib.Logic.Basic` 和 `Mathlib.Data.Set.Defs` 的全部 705 条真实定理，117,338 条数据记录一致。另用官方序列化的 13 个测试项覆盖全部 12 种 `Expr` 构造器。
- Elan 启动器通过 26 项受控测试，其中 16 项与官方 4.2.4 二进制的输出和退出状态一致。回归测试进入 `make test`。
- Elan 的 37 项汇编测试通过。另依据固定上游提交的规则对照了 402,234 个描述符输入和 97,656 个目录名输入。
- Mathlib4 的 16 项汇编测试通过。官方 Lean 4.19.0 接受了从证书生成的 `Nat.succ_injective` 同命题证明。

## Mathlib4 缓存验证与耗时

用 Lean 4.19.0 的 `Lean.readModuleData` 编译对照程序。在 83 个真实 `.olean` 模块上，模块计数和 15,582 条声明的分类查询结果均与汇编工具一致。30 项独立汇编测试通过。

对官方缓存的 `Mathlib/Data/Nat/Basic.olean` 预热后，分别为两种实现启动 31 次进程。下表为中位耗时，计入进程启动、文件访问、查询和输出。

| 相同的查询 | 使用官方 Lean 接口的对照程序 | 汇编读取器 |
| --- | ---: | ---: |
| 查询 `Nat.succ_injective` | 25.498 ms | 0.282 ms |
| 批量查询同一模块的 49 条声明 | 24.498 ms | 0.301 ms |

该测试只比较单模块的缓存元数据查询，未测量完整导入、编译或证明复核。不同机器和冷缓存下的耗时可能不同。

## 递归缓存查询核验

导入路径在 1,555 个真实 `.olean` 上与 Lean 对照，5,397 个普通导入路径一致，另外验证了仅运行时导入跳过。36 项查询与官方 `Lean.importModules` 及基于 `Lean.readModuleData` 的逐模块查找结果一致。随包测试覆盖菱形依赖、路径优先级、提前命中和缺失状态。

以 `Mathlib.Data.Nat.Basic` 的真实缓存为入口，对比两种广度优先的声明查询。预热文件缓存后各运行 11 次，计入进程启动和输出，取中位耗时。对照程序用 Lean 的 `Lean.readModuleData` 读取模块。

| 查询 | 访问模块数 | Lean 对照 | 汇编 |
| --- | ---: | ---: | ---: |
| 单个根模块声明 | 1 | 25.800 ms | 0.466 ms |
| 9 条本地及传递依赖声明 | 171 | 31.886 ms | 3.522 ms |
| 上述 9 条加一条缺失声明 | 1,307 | 64.691 ms | 21.100 ms |

上述结果衡量缓存声明查询。缓存下载、Lean 环境构建和内核证明复核均不计时。

## 覆盖范围

Lean 4 的编译器、内核、标准库、Lake 和其余运行时代码待移植。Elan 的默认和目录覆盖选择、远程版本解析、下载、安装、缓存和自更新待移植。Mathlib4 的定理内核复核、声明写入、策略与元程序待移植。汇编证明证书目前使用原型格式。`.olean` 读取器可在固定版本的单个模块及其导入模块中查询声明。完整 Lean 环境构建、内核证明复核和缓存写入仍由上游工具负责。导出的定理记录里，`mdata` 条目的任意元数据按文件偏移保留引用。三个完整上游项目的构建和测试套件未运行。
