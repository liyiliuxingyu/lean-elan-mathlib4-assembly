# Lean 表达式与宇宙层级的缓存字段

`kernel-data.s` 实现了 Lean v4.19.0 的 12 个 C 导出符号。表达式和宇宙层级的构造器已经计算了哈希、变量标志和深度等信息。汇编函数直接读取原生 Lean 对象，在常数时间内返回查询结果。目标是官方 Linux x86-64 发行版的 System V AMD64 ABI，固定提交为 `6caaee842e9495688c1567e78c0e68dbb96942aa`。[Expr.lean](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Expr.lean#L605-L612) · [Level.lean](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Level.lean#L125-L128)

| C 导出符号 | C 返回类型 | 含义 |
| --- | --- | --- |
| `lean_expr_hash` | `uint64_t` | 低 32 位存放表达式哈希，高 32 位为零 |
| `lean_expr_has_fvar` | `uint8_t` | 含自由变量 |
| `lean_expr_has_expr_mvar` | `uint8_t` | 含表达式元变量 |
| `lean_expr_has_level_mvar` | `uint8_t` | 含宇宙层级元变量 |
| `lean_expr_has_mvar` | `uint8_t` | 含上述任一种元变量 |
| `lean_expr_has_level_param` | `uint8_t` | 含宇宙层级参数 |
| `lean_expr_loose_bvar_range` | `uint32_t` | 最大未绑定 de Bruijn 索引加一，全部已绑定时为零 |
| `lean_expr_binder_info` | `uint8_t` | 返回 `lam` 或 `forallE` 的 `BinderInfo`，其余构造器返回 `default` |
| `lean_level_hash` | `uint32_t` | 宇宙层级哈希 |
| `lean_level_has_mvar` | `uint8_t` | 含宇宙层级元变量 |
| `lean_level_has_param` | `uint8_t` | 含宇宙层级参数 |
| `lean_level_depth` | `uint32_t` | 宇宙层级的 24 位深度字段 |

## 对象所有权与运行时依赖

每个入口均在 `rdi` 接收一个所拥有的 Lean 对象引用，返回时已消费该引用。调用者若需继续使用对象，应在调用前使用官方 `lean_inc` 增加引用。持久化对象的引用计数保持为零。普通共享对象的引用计数减一。最后一个普通引用和多线程对象交给官方运行时的 `lean_dec_ref_cold` 处理。[lean.h](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/include/lean/lean.h#L477-L507)

`Level.zero` 由立即数表示，哈希为 2221，其余三个查询结果为零。该发行版对其他 `Level` 的每次查询均为一个临时装箱分配记一次心跳。汇编直接读取缓存，并调用 `lean_inc_heartbeat`，使可观察的心跳增量保持一致。调用这些符号的程序需要提供上述两个运行时入口。对象分配、构造、子对象释放和内核类型检查仍使用上游实现。对象布局与心跳行为限定于本次核验的构建版本。

## 复现对照

在源码根目录运行。默认测试仅需 GNU Make 和 Binutils。对照测试另需 C 链接驱动（可用 `CC` 指定）和官方 Lean v4.19.0 Linux x86-64 发行包。

```sh
make test
make test-kernel-oracle LEAN=/path/to/lean-4.19.0-linux/bin/lean
```

`kernel-data-test.s` 独立检查 12 种表达式标签、6 种层级构造器、4 种绑定方式、缓存字段的位宽及引用释放分支。`kernel-data-oracle.s` 由官方构造器生成 128 组样本。每组对 12 个表达式各调用 8 个入口，对 6 个层级各调用 4 个入口，共产生 15,360 条记录。样本包含自然数和字符串字面量、最大可表示的未绑定索引、单线程与多线程引用及持久化对象。每个对象的最后一个查询消费驱动持有的引用。

测试分别链接只使用官方 `libleanshared.so` 的程序，以及另外链接汇编对象的程序。每条记录包含调用序号、返回值、心跳增量和仍可读取的引用计数。两次运行的输出逐字节比较，默认保存在 `build/lean4/kernel-oracle-{stock,asm}.txt`。

## Mathlib4 实际模块核验

另用官方 Lean v4.19.0 编译了一个调用全部 12 个 C 符号的原生程序。它通过 `Lean.readModuleData` 读取 Mathlib4 v4.19.0 的 `Mathlib.Data.Nat.Basic`、`Mathlib.Data.Nat.Init`、`Mathlib.Data.Set.Defs`、`Mathlib.Logic.Basic`，遍历其中 705 条定理的类型与证明。程序共访问表达式 132,798 次、宇宙层级 13,586 次，同一节点可从不同定理或根表达式重复访问。分别链接官方实现和汇编实现后，1,116,728 个查询返回值全部一致。这项核验覆盖已编译证明的缓存字段。证明的类型检查由 Lean 内核负责。
