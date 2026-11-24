# Lean 4、Elan、Mathlib4 汇编移植

这是三个项目的第七阶段汇编移植源码包。目标是 Linux x86-64、ELF 和 System V AMD64 ABI。产品实现采用 GNU `as` 的 Intel 汇编语法。Makefile 负责组装和链接，测试编排使用 Make 和 shell。

| 项目 | 此版本实现 | 上游基线 |
| --- | --- | --- |
| Lean 4 | `hash_str` 和 `src/runtime/utf8.cpp` 的全部 19 个公开符号，另含 8 个 Expr 和 4 个 Level 数据访问器，函数应用链的 8 个定义、13 个原生入口，以及松散绑定变量的升降下标操作。 | [v4.19.0 · 6caaee842e94](https://github.com/leanprover/lean4/tree/6caaee842e9495688c1567e78c0e68dbb96942aa/src/runtime) |
| Elan | 解析工具链描述符和目录名，可从参数、环境、项目文件和本机设置选择已安装工具链并启动命令，支持列举、链接工具链，定位或运行所选工具链上的命令。 | [v4.2.4 · 227caca13372](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-dist/src/dist.rs) |
| Mathlib4 | 将 `Nat.succ_injective` 表示为汇编数据，提供汇编证明检查器和 Lean 证明导出程序。直接查询编译好的 `.olean`，可沿导入遍历、批量索引声明、导出定理的类型、证明和元数据。可直接读取 `.ltar`、建立跨归档声明索引，并用任意精度自然数执行 `Nat.pair` 和 `Nat.unpair`。 | [v4.19.0 · c44e0c8ee63c](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Mathlib/Data/Nat/Basic.lean#L55) |

## 构建与验证

在 Linux x86-64 上使用 GNU Make、Binutils 及常见的 POSIX 命令行工具，从本目录运行。

```sh
make
make test
```

构建产物按项目存放在 `build/{lean4,elan,mathlib4}/`。其中包括 Lean 汇编静态库、本地工具链管理器、启动代理、证明导出程序，以及读取 `.ltar`、LGZ 流和 `.olean` 的三个命令。

```sh
build/elan/elan-asm-descriptor parse leanprover/lean4:v4.19.0
build/elan/elan-asm-descriptor dir leanprover--lean4---v4.19.0
build/elan/elan-asm-run /path/to/lean-4.19.0-linux lean --version
build/elan/elan-asm-proxy lean +/path/to/lean-4.19.0-linux --version
build/elan/elan toolchain list
build/mathlib4/export-lean
make test-upstream LEAN=/path/to/lean-4.19.0-linux/bin/lean
build/mathlib4/mathlib-ltar --list /path/to/cache.ltar
# 以下两条命令使用 Mathlib/Data/Set/Defs 对应的归档
build/mathlib4/mathlib-ltar --lookup SetDefs.ltar Set.ext
build/mathlib4/mathlib-ltar --term SetDefs.ltar Set.ext
build/mathlib4/mathlib-olean --term /path/to/Mathlib/Data/Nat/Basic.olean Nat.succ_injective
```

`make test` 运行独立的汇编测试。`make test-lean` 需要官方 Lean v4.19.0。它把证明证书转换为 Lean 源码，再由官方 Lean 检查该命题的证明。`make test-upstream` 还会用系统链接驱动和官方 Lean 动态库分别链接对照程序，逐行比较原生数据访问器、函数应用链以及松散绑定变量位移入口的结果。

## 第七阶段

- **跨归档缓存查询**。为一批 `.ltar` 建立一次本地索引，随后按声明名称查种类和来源文件，或直接按定理名称导出证明。在固定版本 `Mathlib/Data/Nat/` 下全部 80 个模块上核对了 4,786 条声明。3,134 个定理共 709,180 行类型和证明图与查询官方解包文件的结果逐字节一致。[命令、优先级与文件格式](mathlib4/CATALOG.md) · [真实样本与计时](mathlib4/CATALOG-CORPUS.md) · [自然数目录全量核对](mathlib4/CATALOG-NAT-CORPUS.md)
- **Mathlib4 自然数配对**。新增两个真正执行数学计算的汇编函数 `Nat.pair`、`Nat.unpair`。独立程序支持超出 64 位的自然数，包含多精度算术与整数平方根。对公开缓存中编译出的上游实现完成了 1,848 次正反向对照。可用 `build/mathlib4/mathlib-pairing pair 3 5` 得到 28，反向运行 `unpair 28` 得到 `3 5`。[定义与对照测试](mathlib4/PAIRING.md)
- **Lean 绑定变量**。移植表达式中松散绑定变量的下标提升和降低，包括两个闭包入口。对 13 个模块中 61 个定理的 3,197 个表达式节点，与官方内核接口对照 38,364 次，比较返回结构、原节点是否复用和心跳增量。[运行时依赖与验证](lean4/EXPR-SHIFT.md)
- **Elan 本地命令**。新增 `elan which COMMAND` 和 `elan run TOOLCHAIN COMMAND [ARG...]`，用于定位命令和在已安装工具链下启动进程。另用官方 Elan 4.2.4 核对了 150 次离线调用的输出和退出状态。[Elan 管理命令](elan/MANAGER.md)

## 第六阶段

- **Mathlib4 压缩缓存**。`mathlib-ltar --lookup` 和 `--term` 在内存中还原选中的模块，`--cat` 可输出指定成员。13 份真实缓存的 91 个成员都与 leantar 0.1.15 解包结果逐字节相同。官方 Lean 枚举的 1,804 个声明和额外 13 次缺失查询均符合预期，61 个定理导出的 5,292 行类型和证明记录与读取已解包模块的结果一致。[命令和格式](mathlib4/LTAR.md) · [LGZ 对象重建](mathlib4/lgz.md)
- **Lean 4**。新增查找函数头、统计和收集参数、按上限剥离函数应用等 8 个定义，共 13 个 ABI 入口。用官方 v4.19.0 在 97 组对象图上逐入口对照，1,261 条记录一致。生成数组、处理大自然数和释放引用仍调用 Lean 运行时。[应用链入口与验证](lean4/EXPR-APP.md)
- **Elan**。`elan toolchain link NAME PATH` 注册已有的本地工具链，`elan toolchain list` 按上游规则列举。65 个场景的标准输出、标准错误、退出状态与目录状态均与 Elan v4.2.4 一致。其中一项对 1,548 个名称排序。[本地工具链管理](elan/MANAGER.md)

这批缓存共有 39 个 Zstandard 帧、70 个压缩块。汇编解码结果与系统 libzstd 逐字节一致。Zstandard 字典沿用 leangz v0.1.15 的 486,250 字节静态数据，以汇编数据指令保存。缓存命令和本地 Elan 命令均静态链接。热缓存单核测试中，从压缩包导出 `Set.ext` 的中位耗时为 1.832 ms，先强制解包再查为 8.429 ms，查询已有 `.olean` 为 0.257 ms。真实缓存的下载标识、校验和、声明核对及测速方法见[真实缓存验证记录](mathlib4/LTAR-CORPUS.md)。

## 第五阶段新增能力

- **Lean 4** 的原生访问器处理表达式哈希、变量标志、绑定方式，以及宇宙层级的哈希、深度和参数标志。用官方库对照的 15,360 条测试记录逐字节相同。另在 705 条真实定理上核对了 1,116,728 个返回值。[原生 ABI 与复现命令](lean4/KERNEL-DATA.md)
- **Elan** 新增 `elan-asm-proxy`。在实际项目目录运行 `elan-asm-proxy lean --version` 即可检查所选工具链。支持目录覆盖、祖先目录中的 `lean-toolchain` 及 `leanpkg.toml`、安装目录和默认工具链。138 次成功启动的标准输出、标准错误与退出状态和官方 Elan 4.2.4 相同。设置格式和选择优先级见[本地工具链选择](elan/SELECTION.md)。
- **Mathlib4** 的 `--term` 可展开全部六种 `DataValue`，包括嵌套语法、语法位置、共享文本及有符号大整数。从四个真实模块导出的 705 条定理共 117,664 条图记录，与 `Lean.readModuleData` 对照一致，另核对了每条定理的两个根偏移。`mathlib-ltar` 能读取未解包归档的目录和注释。对照了 76 个真实归档的 532 条成员记录。[元数据记录格式](mathlib4/TERM-METADATA.md) · [压缩缓存目录](mathlib4/LTAR.md)

## 第五阶段批量缓存查询耗时

用同一组参数对第四阶段和第五阶段汇编读取器交替计时，预热文件页缓存，计入进程启动、查找以及写出结果的时间。真实文件的正确性由使用官方 Lean 4.19.0 接口的独立程序核对。84 个模块共 17,828 条声明的输出、缺失项和重复查询均通过比较。其中 59 个模块达到了索引门槛，含 17,044 条声明。

| 查询工作量 | 第四阶段中位数 | 第五阶段中位数 |
| --- | ---: | ---: |
| `Mathlib.Data.Nat.Init` 全部 502 条声明 | 1.760 ms | 0.433 ms |
| `Mathlib.Tactic.Linter.FlexibleLinter` 全部 917 条声明 | 7.424 ms | 3.202 ms |
| `Lean.Meta.Basic` 全部 2,246 条声明 | 26.130 ms | 8.127 ms |
| 从 `Mathlib.Data.Nat.Basic` 递归查询 130 个混合名称 | 35.515 ms | 35.185 ms |
| 从同一入口递归查询 128 个均缺失的名称 | 202.318 ms | 54.378 ms |

单文件各计时 31 次，递归各计时 17 次。两组递归查询均访问 1,307 个模块。混合组取 `Mathlib.Data.Nat.Init` 声明表中每四条的第一条，再加入根模块声明、重复的 `Nat.succ` 和一个缺失名。该组中位数接近；明显提速出现在同一文件的大批量查询和持续存在大量缺失名称的递归查询。测试没有计入下载、解压、编译和内核证明检查。

## 第一至四阶段验证记录

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

当前包中的产品代码、二进制夹具及调用官方 ABI 的测试驱动使用 GNU 汇编。构建与测试编排使用 Make 和 shell，部分可选对照测试使用上游 Lean 定义或从官方缓存提取的 C。独立的缓存命令无需安装 Lean。接入官方 Lean 进程时，部分运行时符号仍依赖其内存管理和 C++ ABI；Elan 启动的工具链命令使用所选工具链原有的可执行文件。

Lean 的完整内核、编译器、标准库及 Lake，Elan 的联网下载、安装和自更新，以及 Mathlib4 全部定理和策略的源码移植仍待完成。读取缓存中的证明和元数据后，通用证明类型检查仍由 Lean 内核承担。三个完整上游项目的全套测试尚未运行。
