# 遍历 Lean 函数应用

`expr-app.s` 为 Lean v4.19.0 的 8 个 `Lean.Expr` 定义提供 13 个原生 ELF 入口。它们沿 `Expr.app f a` 的函数字段遍历应用链。以 `((f a) b)` 为例，函数头是 `f`，参数依次是 `a`、`b`。绑定体、参数内部及头部常量的定义均不展开。固定版本为 Linux x86-64 发行版提交 `6caaee842e9495688c1567e78c0e68dbb96942aa`。[Lean 定义](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Expr.lean#L1064-L1162) · [上游生成的 C 入口](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/stage0/stdlib/Lean/Expr.c#L25553-L26098)

| Lean 定义 | ELF 名称（省略前缀 `l_Lean_Expr_`） | 返回值 |
| --- | --- | --- |
| `getAppFn` | `getAppFn`、`getAppFn___boxed` | 应用链的头部表达式 |
| `getAppFn'` | `getAppFn_x27`、`getAppFn_x27___boxed` | 穿过函数位置的 `mdata` 后得到的头部表达式 |
| `getAppNumArgs` | `getAppNumArgs`、`getAppNumArgs___boxed` | 参数个数，类型为 Lean `Nat` |
| `getAppNumArgs'` | `getAppNumArgs_x27`、`getAppNumArgs_x27___boxed` | 穿过函数位置的 `mdata` 后得到的参数个数 |
| `getBoundedAppFn` | `getBoundedAppFn`、`getBoundedAppFn___boxed` | 从最外层剥去至多 `maxArgs` 个参数后剩下的表达式 |
| `getAppArgs` | `getAppArgs` | 按调用顺序排列的 `Array Expr` |
| `getAppRevArgs` | `getAppRevArgs` | 按相反顺序排列的 `Array Expr` |
| `getBoundedAppArgs` | `getBoundedAppArgs` | 最外层至多 `maxArgs` 个参数，按调用顺序排列 |

单参数入口在 `rdi` 接收表达式。带上限的入口在 `rdi` 接收一个拥有的 Lean 自然数，在 `rsi` 接收表达式。函数头和计数的普通入口借用表达式，带 `___boxed` 后缀的入口消费表达式。三个数组入口均消费表达式。所有返回值均在 `rax` 中交付给调用者，由调用者遵循 Lean 的引用计数规则释放。[运行时对象与引用计数](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/include/lean/lean.h#L473-L507)

遍历使用固定大小的栈空间。数组与输入表达式共享参数对象，可保留重复参数的对象身份。数组按精确容量一次分配，随后从一端填入已持有的参数引用。`maxArgs` 支持立即数和多精度自然数。本实现链接官方运行时的 `lean_mk_array`、`lean_nat_big_sub`、`lean_inc_ref_cold` 与 `lean_dec_ref_cold`。[运行时数组分配](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/runtime/object.cpp#L2441-L2462)

## 复现测试

在工程根目录执行以下命令。

```sh
make test-expr-app
make test-expr-app-oracle LEAN=/path/to/lean-4.19.0-linux/bin/lean
```

第一项仅需 GNU Make 和 Binutils，覆盖不同头部标签、嵌套元数据、边界、引用计数路径和 4,096 层应用链。第二项需要 C 链接驱动与指定的官方 Lean 发行版。驱动以官方构造器生成 97 组输入，每组分别调用全部 13 个入口。样本包含重复参数、函数和参数共享子树、1,024 层应用链、根的最后一个引用、多线程对象、持久化对象、最大立即自然数及两个多精度自然数。

对照程序分别链接原版共享库和加入汇编对象的共享库调用方，比较 1,261 条记录。每条记录核对返回值、可观测引用计数与心跳增量。数组逐项记录构造时分配的对象编号，同时核对长度和容量。两组输出保存在构建目录的 `lean4/expr-app-{stock,asm}.txt`。

另以官方 `lean_read_module_data` 读取[缓存对照语料](../mathlib4/LTAR-CORPUS.md)中的全部 61 个定理。从类型与证明根开始，按模块去重得到 3,197 个表达式节点。在同一进程中对每个节点调用汇编及官方实现的全部 13 个入口，41,561 对结果及心跳增量均一致。函数头比较原生对象指针，数组比较长度、容量和每个元素的对象指针。
