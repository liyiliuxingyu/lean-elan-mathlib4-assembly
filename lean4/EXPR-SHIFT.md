# Lean 内核的松散绑定变量位移

`expr-shift.s` 实现 Lean 4.19.0 的 `Lean.Expr.liftLooseBVars` 和 `Lean.Expr.lowerLooseBVars`。例如，在类型已闭合的表达式 `fun x : T => (#0 #2)` 中，`#0` 指向 `x`，`#2` 指向外层变量。以起点 0、位移 1 执行提升，得到 `fun x : T => (#0 #3)`。在结果上以起点 1、位移 1 执行降低，可得到原来的结构。[Lean 定义](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/Lean/Expr.lean#L1293-L1305) · [固定版本内核实现](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/kernel/expr.cpp#L388-L446)

| System V AMD64 入口 | 输入所有权 | 结果 |
| --- | --- | --- |
| `lean_expr_lift_loose_bvars` | 借用表达式、起点和位移 | 返回调用方持有的表达式 |
| `lean_expr_lower_loose_bvars` | 借用表达式、起点和位移 | 返回调用方持有的表达式 |
| `l_Lean_Expr_liftLooseBVars___boxed` | 消费三个参数 | 同上 |
| `l_Lean_Expr_lowerLooseBVars___boxed` | 消费三个参数 | 同上 |

四个入口均在 `rdi`、`rsi`、`rdx` 接收表达式、Lean 自然数起点和位移，使用 `rax` 返回结果。在此版本的 C 入口，任一自然数采用多精度堆对象表示时，直接返回输入表达式。降低操作还会按完整的立即自然数检查起点是否小于位移。通过这些检查后，内核将参数缩窄为 32 位无符号数。位移为零、或表达式缓存的松散变量范围已经排除目标时，返回原对象并遵守相应的所有权约定。[生成的闭包入口](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/stage0/stdlib/Lean/Expr.c#L26957-L26977)

汇编按指针字段遍历表达式。进入 lambda、forall 或 let 的主体时，绑定深度加一。在绑定类型、let 的值、应用两侧、元数据和投影的子表达式中，深度不变。节点内的实际阈值为起点加当前深度。加法溢出或阈值超出该节点的松散变量范围时可跳过整棵子树。遇到有效的 `bvar` 才修改下标。只有子表达式发生变化时才重建父节点。重建 lambda 和 forall 时保留绑定信息。重建 let 时与 v4.19.0 内核一致，将 `nonDep` 置为假。[上游更新逻辑](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/kernel/expr.cpp#L278-L332)

一次调用使用独立哈希表，以输入节点指针和绑定深度为键。深度相同的共享子表达式可重复使用同一个结果，同一输入节点出现在不同深度时分别处理。表中结果持有引用，调用结束时统一释放。递归栈随访问深度增长。遍历、索引运算、缓存和引用转移由本项目汇编实现。节点构造、冷路径引用计数以及多精度自然数运算调用官方 Lean 运行时，前 16 个缓存槽位于本次调用的栈上，扩容和释放由汇编直接使用 Linux 的匿名内存映射完成。[上游遍历与缓存](https://github.com/leanprover/lean4/blob/6caaee842e9495688c1567e78c0e68dbb96942aa/src/kernel/replace_fn.cpp#L15-L94)

## 复现

在工程根目录执行以下命令，第二项使用与[公开缓存语料](../mathlib4/LTAR-CORPUS.md)相同的 13 个归档以及 leantar 0.1.15。

```sh
make test-expr-shift-oracle LEAN=/path/to/lean-4.19.0-linux/bin/lean
make test-expr-shift-corpus LEAN=/path/to/lean-4.19.0-linux/bin/lean \
  LEANTAR=/path/to/leantar LTAR_CORPUS=/path/to/archives
```

构造测试比较 4,320 条记录。18 个表达式图分别使用单线程、多线程和持久化引用计数，配合 20 组起点和位移，逐一调用四个入口。样本覆盖 12 个表达式标签、多个深度上的共享、256 层绑定、带标记的 let、包含数据的元数据、32 位参数缩窄及堆自然数。测试逐字段序列化结果，并比较缓存数据、输入和输出节点身份、可观测引用计数和心跳增量。每次释放结果后，还会校验原对象的引用计数。两项附加断言专门检查闭包入口消费根对象最后一个引用后，其旧子节点的引用是否已释放。

语料测试核对归档的 SHA-256，再用官方 `lean_read_module_data` 读取 13 个模块。从 61 个定理的类型和证明根出发，按模块内对象身份去重得到 3,197 个表达式节点。每个节点用六组参数调用提升与降低的借用入口，共 38,364 对结果。官方结构相等判断、是否返回输入指针和心跳增量均一致，其中 26,805 对调用返回了不同于输入的根对象。
