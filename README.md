# Lean 4、Elan、Mathlib4 汇编移植

这是三个项目的首批源码。目标是 Linux x86-64、ELF 和 System V AMD64 ABI。实现与自测采用 GNU `as` 的 Intel 汇编语法。Makefile 负责组装、链接和运行测试。

| 项目 | 此版本实现 | 上游基线 |
| --- | --- | --- |
| Lean 4 | `hash_str` 和 11 个 UTF-8 入口，包括两组 C/C++ 长度函数、字符解码、校验和编码。保留这些入口的原符号及参数约定。 | [v4.19.0 · 6caaee842e94](https://github.com/leanprover/lean4/tree/6caaee842e9495688c1567e78c0e68dbb96942aa/src/runtime) |
| Elan | 解析已解析的工具链描述符和目录名，提供可单独链接的函数和示例命令。 | [v4.2.4 · 227caca13372](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-dist/src/dist.rs) |
| Mathlib4 | 将 `Nat.succ_injective` 表示为汇编数据，提供汇编证明检查器和 Lean 证明导出程序。 | [v4.19.0 · c44e0c8ee63c](https://github.com/leanprover-community/mathlib4/blob/c44e0c8ee63ca166450922a373c7409c5d26b00b/Mathlib/Data/Nat/Basic.lean#L55) |

## 构建与验证

在 Linux x86-64 上安装 GNU Make 和 GNU Binutils 后，从本目录运行。

```sh
make
make test
```

`make` 生成 `build/lean4/liblean-asm-runtime.a`、`build/elan/elan-asm-descriptor` 和 `build/mathlib4/export-lean`。

```sh
build/elan/elan-asm-descriptor parse leanprover/lean4:v4.19.0
build/elan/elan-asm-descriptor dir leanprover--lean4---v4.19.0
build/mathlib4/export-lean
make test-lean LEAN=/path/to/lean
```

`make test` 运行独立的汇编测试。最后一条命令需要官方 Lean v4.19.0。它把证明证书转换为 Lean 源码，再由官方 Lean 检查该命题的证明。证书格式、信任范围和 Elan 的接口约定见子目录说明。

## 本次验证结果

- 哈希与固定提交编译出的 C++ 实现逐项比较 18,344 次，覆盖非对齐输入、尾部长度、随机种子和内存页边界。
- UTF-8 的 11 个入口与官方 Lean 4.19.0 发行版直接对照，覆盖全部 256 个单字节分类和 65,536 种双字节输入，以及固定种子的随机用例。
- Elan 的 37 项汇编测试通过。另依据固定上游提交的规则对照了 402,234 个描述符输入和 97,656 个目录名输入。
- Mathlib4 的 16 项汇编测试通过。官方 Lean 4.19.0 接受了从证书生成的 `Nat.succ_injective` 同命题证明。

## 覆盖范围

Lean 4 的编译器、内核、标准库、Lake 和其余运行时代码待移植。Elan 的工具链查找、版本选择、下载、安装、缓存、代理及自更新待移植。Mathlib4 的其余声明、证明、策略与元程序待移植。汇编证明证书目前使用原型格式，尚无 `.olean` 读写实现。三个完整上游项目的构建和测试套件未运行。
