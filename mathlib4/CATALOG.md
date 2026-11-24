# 跨压缩归档查询声明

`mathlib-catalog` 为一组本地 `.ltar` 建立可重复使用的声明索引。索引记录声明种类、完整名称和来源归档，不保存解包后的 `.olean`。构建时按命令行顺序逐个解码归档。名称查询只映射索引文件，导出证明时才解码命中的模块。

从仓库根目录构建。下面的例子适用于包含 `Mathlib.Data.Set.Defs` 的缓存集。

```sh
make
build/mathlib4/mathlib-catalog build mathlib.idx /path/to/cache/*.ltar
build/mathlib4/mathlib-catalog stats mathlib.idx
build/mathlib4/mathlib-catalog lookup mathlib.idx Set.ext Set
build/mathlib4/mathlib-catalog term mathlib.idx Set.ext > Set.ext.tsv
```

| 命令 | 输出和使用条件 |
| --- | --- |
| `build INDEX ARCHIVE...` | 成功后在指定位置生成索引，或原子替换已有的同格式索引。每个输入文件须包含唯一一个可解码的 LGZ 类型 `.olean`。构建失败时已经发布的索引仍可读取。 |
| `stats INDEX` | 列出输入归档数、已索引声明记录数、超出查询名称语法的记录数。同名声明在记录数中分别计数。 |
| `lookup INDEX NAME...` | 每个命中输出三列 TSV，依次为种类、输入名称、建索引时的绝对归档路径。缺失时输出两列 `missing` 和输入名称。结果按参数顺序排列，重复查询保留。同名声明取输入顺序靠前的归档及该模块内靠前的记录。 |
| `term INDEX THEOREM` | 重新打开命中的归档，比较完整归档的 XXH64 与构建时的记录，核对当前模块中的名称、种类，再输出与 `mathlib-ltar --term` 同格式的类型与证明图。归档路径失效或内容已改变时返回错误。 |

`lookup` 的结果反映构建时的内容。源归档移走后仍能查到原路径。归档集合、内容或位置更新后可重跑 `build`。索引本身可放在其他目录。路径输出中的制表符、换行、反斜杠及其他 ASCII 控制字节以 `\xHH` 转义。`lookup` 和 `term` 成功返回 0，指定声明缺失返回 1，参数、I/O、格式错误和把非定理交给 `term` 时返回 2。

若想同时读取本阶段移植的配对函数和上游逆函数定理，可以使用公开的 `Mathlib.Data.Nat.Pairing` 归档。在项目根目录执行以下命令。

```sh
cache=$(mktemp -d)
curl -fLsS https://lakecache.blob.core.windows.net/mathlib4/f/836f4072582cbc3e.ltar \
    -o "$cache/836f4072582cbc3e.ltar"
build/mathlib4/mathlib-catalog build "$cache/pairing.idx" "$cache/836f4072582cbc3e.ltar"
build/mathlib4/mathlib-catalog lookup "$cache/pairing.idx" Nat.pair Nat.unpair_pair
build/mathlib4/mathlib-catalog term "$cache/pairing.idx" Nat.unpair_pair > "$cache/unpair_pair.tsv"
```

在该版本上，两个查询分别返回定义和定理，最后一条命令导出 761 行类型与证明记录。这个归档和所用上游生成代码的校验方式见[配对函数对照](PAIRING.md)。

## 名称与文件格式

名称解析复用 `mathlib-olean` 的代码。一个名称最多含 64 个分量，数字分量支持 0 到 2⁶³−1。例如 `A.007` 和 `A.7` 对应同一个数字分量，`A.«7»` 对应字符串分量。带点的字符串分量可写成 `A.«has.dot»`。合法的序列化名称如超出可查询范围，会计入 `unqueryable`。指针无效、名称前缀成环或声明记录损坏时，构建报错。

磁盘格式 `MLCAT001` 依次存放 64 字节文件头、模块记录、声明记录、哈希槽表和字节区。名称按从根到叶的顺序编码，每个分量区分字符串或数字，字符串保留字节长度。查询先用 XXH64 选择槽，再比较完整键。槽数为二的幂，表的装填率至多为一半。文件记录使用小端整数和相对偏移。读取器检查段长度，并在探查时检查记录和路径的边界。

缓存兼容范围为本项目固定的 Lean 4.19.0 Linux x86-64 格式。另对固定版本 `Mathlib/Data/Nat/` 下全部 80 个模块逐条核对声明种类、来源和定理导出结果。[跨归档查询计时](CATALOG-CORPUS.md) · [自然数模块清单与复现命令](CATALOG-NAT-CORPUS.md)
