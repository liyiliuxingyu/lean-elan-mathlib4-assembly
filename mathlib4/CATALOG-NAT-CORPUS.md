# Mathlib 自然数目录的完整缓存对照

对 Mathlib4 v4.19.0 的 `Mathlib/Data/Nat/` 源码树递归列举，得到 80 个 Lean 模块；80 份对应的官方发布缓存均已取得，共 1,659,929 字节。按模块名排序建索引后，官方 Lean 枚举的 4,786 条声明均可查到，名称、类别和来源归档逐条一致。[固定版本源码树](https://github.com/leanprover-community/mathlib4/tree/c44e0c8ee63ca166450922a373c7409c5d26b00b/Mathlib/Data/Nat) · [80 份归档的模块名、文件名与 SHA-256](catalog-nat-corpus.tsv)

| 声明类别 | 条数 |
|---|---:|
| 定理 | 3,134 |
| 定义 | 1,590 |
| 公理 | 53 |
| 归纳类型 | 3 |
| 构造器 | 3 |
| 递归器 | 3 |
| 合计 | 4,786 |

官方 leantar 0.1.15 独立解包每份归档。测试驱动链接官方 Lean 4.19.0 共享库，从原始 `.olean` 枚举每项 `ConstantInfo` 的类别，并用 Lean 的 `Name.toString` 得到查询名。以最多 200 个声明为一组，逐条核对查询结果的名称、类别和归档路径。24 组查询各附加一个不存在的名称，并检查缺失行和退出状态。

4,786 项的名称互异。另将 `Mathlib.Data.Nat.Pairing` 的原件和副本同时建入索引，再交换两者顺序。对 `Nat.pair`、`Nat.unpair`、`Nat.unpair_pair` 和 `Nat.pair_unpair` 的查询均指向当次排在前面的归档。

对全部 3,134 个定理，`mathlib-catalog term` 从压缩归档导出的类型及证明表达式，与 `mathlib-olean --term` 直接读取官方解包文件所得的 TSV 逐字节相同。共比较 709,180 行、21,680,506 字节。这项测试衡量两条读取路径导出的表达式记录是否相同。默认抽样模式读取每个含定理模块的首个定理，并覆盖两个配对逆函数定理，共 81 个表达式图、21,481 行。

## 复现

以下命令在本项目根目录执行。依赖 GNU Make、Binutils、C 链接驱动、官方 Linux x86-64 Lean 4.19.0、leantar 0.1.15，以及支持并发下载的 curl。测试在建索引前校验清单中每份归档的 SHA-256，逐个确认解包的模块路径。

```sh
cache=$(mktemp -d)
manifest="$PWD/mathlib4/catalog-nat-corpus.tsv"
awk -F '\t' '{ print "url = \"https://lakecache.blob.core.windows.net/mathlib4/f/" $2 "\""; print "output = \"" $2 "\"" }' \
    "$manifest" > "$cache/urls"
(cd "$cache" && curl --parallel --parallel-max 6 --fail --silent --show-error --retry 2 --config urls)
make -C mathlib4 test-catalog-nat-corpus NAT_CORPUS="$cache" NAT_ALL_TERMS=1 \
    LEAN=/path/to/lean-4.19.0/bin/lean LEANTAR=/path/to/leantar
```

`NAT_ALL_TERMS=0` 选择抽样表达式图；两种模式都覆盖全部 4,786 条声明。要核对清单覆盖范围，可从 Mathlib 的 Git 仓库比较源码模块列表。

```sh
git -C /path/to/mathlib4 ls-tree -r --name-only v4.19.0 -- Mathlib/Data/Nat/ \
    | sed -n 's!\.lean$!!p' | tr / . | LC_ALL=C sort > "$cache/source-modules"
cut -f1 "$manifest" | cmp "$cache/source-modules" -
```

按清单顺序，并保留每个模块自身的声明顺序，得到以下 SHA-256。查询结果中的来源归档以文件名记录，使其可跨目录复现。

| 内容 | SHA-256 |
|---|---|
| 全部查询应返回的声明类别、名称和来源归档 | `ac22bf2c648d82a4cb7c3e211872210523f9a4758c1b889f3826bfe95f1a7818` |
| 81 个抽样表达式图拼接的 TSV | `a5c906dd49c34e0a01bf7d9456070ba3696264a12c108c5ce24f45199ea3d211` |
| 3,134 个表达式图拼接的 TSV | `8390a6193a29e24afa5577ac3cd8cf5a0d45f3d073db21b6e79ece42f93d0e09` |
