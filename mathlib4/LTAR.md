# 直接查看 mathlib 的 .ltar 缓存

`mathlib-ltar` 是 Linux x86-64 汇编程序。它可以从本地归档读取版本注释、成员路径、编码方式以及成员在归档中的位置。程序以只读方式映射归档，列目录时跳过压缩内容。可以指定一个成员输出原文件，也可以直接查询归档内模块的声明、定理类型与证明。查询仅在内存中展开选定的 `.olean`，不需要写临时文件。

从项目根目录构建后运行下面的命令。

```sh
make
build/mathlib4/mathlib-ltar -k sample.ltar
build/mathlib4/mathlib-ltar --list sample.ltar
build/mathlib4/mathlib-ltar --cat sample.ltar "$member" > member.out
# 使用 Mathlib/Data/Set/Defs 对应的 .ltar
build/mathlib4/mathlib-ltar --lookup SetDefs.ltar Set.ext Set
build/mathlib4/mathlib-ltar --term SetDefs.ltar Set.ext
```

`-k` 按归档顺序输出每条注释的 UTF-8 字节并追加换行。注释可以为空，也可以包含换行。对本次测试的 76 个 mathlib v4.19.0 缓存，其输出与官方 `leantar 0.1.15 -k` 逐字节相同。

`--list` 每个成员输出一行四列 TSV，依次为编码、从文件开头起算的字节偏移、归档内存储字节数、路径。偏移指向内容本身，可直接用于读取对应字节区间。路径中的 ASCII 控制字符、DEL 和反斜杠按 `\xHH` 转义，其他 UTF-8 字节原样保留。目录中的压缩文件长度表示归档占用空间；解压后的文件可能更大。

| 编码 | 偏移及长度对应的内容 |
| --- | --- |
| `zstd` | 常规成员的压缩字节 |
| `lgz` | 官方构建使用字典压缩的 LGZ 字节 |
| `hash-plain` | 小端 64 位整数，上游解包为十进制文本 |
| `hash-json` | 小端 64 位整数，上游解包为带空日志的 JSON 构建记录 |
| `header-hash` | LTAR 旧格式用文件头偏移 4 的八字节整数重建第一个 trace 成员 |

程序支持 `LTAR` 和 `LTR2` 两种文件头。它在输出前检查整份目录，包括名称和注释的 UTF-8、结束符、编码编号、长度是否落在文件内。成功返回 0。指定的成员或声明缺失时返回 1。归档缺少可查询的模块、候选成员不唯一、参数有误、目录或压缩数据损坏、写出失败时返回 2。目录检查不验证压缩流内容；文件恰好在完整记录后结束时，是格式允许的归档结尾。

已用 76 个真实缓存核对 532 条成员记录，另测了两代格式、四种成员编码、空注释、路径转义、两份测试归档的每个截断位置，以及大于 4 GiB 的稀疏文件偏移。格式依据为 leangz v0.1.15 的 `src/ltar.rs`，该标签对应提交 `c9266d97703277b680be72bc77226c2b62d1d38d`。

[leangz v0.1.15 的 LTAR 格式实现](https://github.com/digama0/leangz/blob/c9266d97703277b680be72bc77226c2b62d1d38d/src/ltar.rs)

## 读取成员及声明

`--cat FILE MEMBER` 使用成员的完整原始路径（包括可能出现的多组 `./`）。它向标准输出写出与官方解包器相同的文件内容。对于 `lgz` 成员，程序先解 Zstandard 帧，再重建完整的 Lean 对象图。对于哈希与 trace 成员，程序生成相应的十进制文本或 JSON。

`--lookup FILE NAME...` 和 `--term FILE THEOREM` 要求归档包含唯一一个 `lgz` 类型的 `.olean` 成员。一次可批量查多个声明，它们共用同一次解码。查询范围是这个模块。已经解包的多个模块可用 `mathlib-olean --recursive` 遍历导入。输出定理的类型和证明采用与独立 `.olean` 读取器相同的 TSV 格式。

每个压缩成员可以包含多个连续的 Zstandard 帧。程序按顺序拼接普通帧的输出，跳过可跳过帧（skippable frame）的内容。每个普通帧独立初始化解码状态，LGZ 成员的每一帧都可使用 leangz 官方字典。单帧成员直接复用解码器返回的内存。末帧截断、校验和不符或末尾有多余字节时，程序报错，标准输出为空。

普通 Zstandard 成员可以解出零字节，例如仅含完整的可跳过帧，或含有空的普通帧。压缩输入本身为零字节时解码失败。LGZ 成员还须包含有效的 LGZ 头及根对象。常规解码支持原样块、游程块、Huffman、FSE、重复偏移和帧校验和。命令行程序的运行只依赖工程中的汇编对象。[LGZ 对象重建及字典来源](lgz.md)

## 核对解包结果

下面的可选测试使用本机的官方 `leantar 0.1.15` 解包，对照每个归档的注释与所有成员字节。本次测试的 13 份真实归档共含 91 个成员。另用官方 Lean 枚举模块的全部 1,804 个声明，核对其分类和 13 个缺失查询。所有 61 个定理的 5,292 行类型和证明记录均与独立读取已解包模块的结果一致。[样本、校验和及复现命令](LTAR-CORPUS.md)

```sh
make -C mathlib4 test-ltar-oracle \
    LTAR_ARCHIVES=/absolute/path/to/cache \
    LEANTAR=/absolute/path/to/leantar
```
