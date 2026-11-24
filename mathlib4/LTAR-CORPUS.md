# Mathlib 缓存实测

对照语料取自 Mathlib4 v4.19.0 的公开缓存，共 8 个 Mathlib 模块和 5 个 Batteries 模块。文件名中的 16 位十六进制数是缓存标识。各归档的 SHA-256 见 [ltar-corpus.sha256](ltar-corpus.sha256)。[公开缓存示例](https://lakecache.blob.core.windows.net/mathlib4/f/049953d176d7bde9.ltar)

| 缓存标识 | 模块 | 编译缓存字节 | 声明 | 定理 |
| --- | --- | ---: | ---: | ---: |
| `049953d176d7bde9` | `Batteries.Tactic.Lint` | 19,880 | 0 | 0 |
| `0ab89eb71a58afc2` | `Mathlib.Tactic.Linter.Lint` | 288,432 | 124 | 0 |
| `0ecfd22f815cc1b7` | `Mathlib.Data.Set.Defs` | 529,024 | 205 | 2 |
| `2bf35fe21b46706e` | `Batteries.Tactic.Lint.Basic` | 613,392 | 302 | 6 |
| `2bfa5a283632be06` | `Mathlib.Order.Defs.PartialOrder` | 288,792 | 190 | 46 |
| `2cb5876227fb6c9c` | `Mathlib.Tactic.Simproc.ExistsAndEq` | 274,704 | 55 | 1 |
| `349dd69a348c6509` | `Batteries.Tactic.Exact` | 59,168 | 10 | 0 |
| `3e373869e7df37e7` | `Batteries.Util.ProofWanted` | 226,296 | 108 | 0 |
| `c57481a6c4f953d5` | `Mathlib.Util.AssertExistsExt` | 229,208 | 89 | 3 |
| `e546ac8a41f2e5e5` | `Mathlib.Tactic.DeclarationNames` | 164,480 | 48 | 0 |
| `e65beb64d2a29355` | `Batteries.CodeAction.Deprecated` | 385,824 | 70 | 0 |
| `f0850058561c679f` | `Mathlib.Tactic.Linter.Style` | 1,209,672 | 555 | 0 |
| `fafb5bd61019f015` | `Mathlib.Data.Ordering.Basic` | 85,352 | 48 | 3 |

## 复现逐字节对照

在工程根目录运行以下命令，需要 GNU Make、Binutils、C 链接驱动、官方 Linux x86-64 Lean v4.19.0 和 leantar v0.1.15。若已有这些归档，可直接指定其所在目录。

```sh
corpus=$(mktemp -d)
while read -r digest file; do
  curl -fLsS "https://lakecache.blob.core.windows.net/mathlib4/f/$file" -o "$corpus/$file" || exit 1
done < mathlib4/ltar-corpus.sha256
make -C mathlib4 test-ltar-corpus LTAR_CORPUS="$corpus" \
  LEAN=/path/to/lean-4.19.0-linux/bin/lean LEANTAR=/path/to/leantar
```

测试先校验归档 SHA-256，使用官方 `leantar --jobs 1 -f -x` 解包，再将每个成员与 `mathlib-ltar --cat` 的标准输出逐字节比较。91 个成员共 5,970,567 字节，包含 13 个 LGZ 编码的编译模块、26 个普通 Zstandard 成员、39 个文本哈希和 13 个 JSON 构建记录。按归档标识排序连接全部 13 个解包后的 `.olean`，其 SHA-256 为 `f173a5d889440fc545dc72f6e57e2c0c11346862ca2f684fb4d744dadfdf851b`。

汇编测试驱动 `ltar_corpus_names.s` 链接官方 Lean 共享库，通过 `lean_read_module_data` 枚举模块的 `ConstantInfo`，使用 Lean 自身的 `Name.toString` 输出名称。每个模块做一次批量查找，核对全部 1,804 个声明的名称、种类和顺序，另检查 13 个缺失请求及退出状态。对全部 61 个定理，分别运行 `mathlib-ltar --term` 与 `mathlib-olean --term`，逐字节比较 5,292 行类型与证明记录。此测试覆盖已编译表达式的导出。证明类型检查由 Lean 内核负责。

| 汇总输出 | SHA-256 |
| --- | --- |
| 归档按上表顺序，声明按模块中的官方数组顺序，每组含一条缺失记录 | `4030f61b4773e2695664f2b7ef02f21e796470dc4d08152451e6d3cf90553d86` |
| 所有定理依同序导出的 TSV，直接拼接 | `ee8d3d6126fcde424d5fa750ef65b949d3c55987827e64877be9eb83a74628b2` |

## 热缓存耗时

测试机器为 Intel Xeon Platinum 8573C，三个程序及输入均位于 tmpfs。调度固定在一个逻辑 CPU，标准输出重定向到 `/dev/null`。每个用例包含以下三条路径。

1. `mathlib-ltar --lookup` 或 `--term` 直接查询压缩归档。
2. `leantar --jobs 1 -f -C DIR -x ARCHIVE` 强制重新写出整份归档的所有成员，随后启动 `mathlib-olean` 查询相应文件。每轮复用同一输出目录。
3. 直接运行 `mathlib-olean` 查询预先解包的文件。

每个用例预热各路径 4 次，随后进行 31 轮。轮内使用固定随机种子 61019 打乱三条路径的执行顺序，每条路径顺序执行 5 次。以单调时钟记录整组墙钟时间，除以 5，再对 31 个均值取中位数。耗时包含启动进程，单位为毫秒。

| 请求 | 归档字节 | 直读归档 | 强制解包后查询 | 查询已解包文件 |
| --- | ---: | ---: | ---: | ---: |
| `Batteries.Tactic.Exact` 查找 `Lean.MVarId.assignIfDefEq` | 6,116 | 0.488 | 2.407 | 0.178 |
| `Mathlib.Data.Set.Defs` 导出 `Set.ext` | 41,365 | 1.832 | 8.429 | 0.257 |
| `Mathlib.Tactic.Linter.Style` 查找 `Mathlib.Linter.findCDot` | 97,355 | 3.558 | 16.869 | 0.249 |

这三个用例中，编译缓存已在磁盘上展开时，直接查询 `.olean` 耗时最低。仅有压缩归档时，单次直读快于强制解包整个模块再查询。不同模块大小、磁盘介质、冷热缓存状态和查询内容会影响结果。
