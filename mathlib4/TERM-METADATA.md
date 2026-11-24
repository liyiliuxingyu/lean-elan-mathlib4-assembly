# 从定理缓存读取元数据

在 Linux x86-64 上，`mathlib-olean --term FILE.olean THEOREM` 可读取 Lean 4.19.0 缓存中定理类型和证明的 `Expr.mdata`。输出为 TSV，每行以换行符结束。以下表格的“字段”列从行首的记录名之后开始，按输出顺序排列。

## 元数据和标量

| 记录 | 字段 | 对应的 Lean 数据 |
| --- | --- | --- |
| `expr`，构造器为 `mdata` | 表达式 ID，`mdata`，元数据表头 ID，子表达式 ID | `Expr.mdata md e` |
| `metadata` | 表项 ID，`entry`，键名，值类型，值，下一表项 ID | `KVMap.entries` 中的一个 `(Name × DataValue)` |

ID 是相对当前文件起始位置的十进制字节偏移。按“下一表项 ID”即可还原原始表项顺序。元数据表头或下一表项为 `0` 表示空表。共享表尾和共享语法节点只展开一次，可由多个 ID 引用。读取方应按 ID 关联行，父节点和子节点的输出顺序由遍历队列决定。

| 值类型 | 值字段的编码 |
| --- | --- |
| `string` | 带双引号的字符串。制表、换行等 ASCII 控制字节、DEL、双引号和反斜杠按 `\xhh` 转义，其他字节原样输出。 |
| `bool` | `0` 或 `1`。 |
| `name` | 点分名称。简单 ASCII 字符串分量直接输出，其他字符串分量用 `«»` 包围。分量中的控制字节、反斜杠和字面双角引号按字节转义。自然数分量用十进制表示，匿名名称写作 `[anonymous]`。表项键名也采用此格式。 |
| `nat` | 无符号十进制整数。 |
| `int` | 有符号十进制整数。负数带减号，零写作 `0`。支持固定版本运行时的装箱小整数和 GMP 多精度整数。 |
| `syntax` | 语法节点 ID。`0` 表示 `Syntax.missing`。 |

## 语法和源码位置

| 记录 | 字段 |
| --- | --- |
| `syntax`，构造器为 `node` | 语法 ID，`node`，源码信息，语法类别名，参数数组 ID |
| `syntax`，构造器为 `atom` | 语法 ID，`atom`，源码信息，文本 ID |
| `syntax`，构造器为 `ident` | 语法 ID，`ident`，源码信息，原始拼写的子串 ID，解析名，预解析列表 ID |
| `sourceInfo`，构造器为 `original` | 源码信息 ID，`original`，前导文本的子串 ID，起始字节位置，尾随文本的子串 ID，结束字节位置 |
| `sourceInfo`，构造器为 `synthetic` | 源码信息 ID，`synthetic`，起始字节位置，结束字节位置，canonical 标志（`0` 或 `1`） |
| `substring` | 子串 ID，完整文本 ID，起始字节位置，结束字节位置（半开区间） |
| `syntaxArray` | 参数数组 ID，元素个数 |
| `syntaxArg` | 参数数组 ID，从零开始的元素下标，子语法 ID |
| `preresolved`，构造器为 `namespace` | 列表项 ID，`namespace`，命名空间名，下一表项 ID |
| `preresolved`，构造器为 `decl` | 列表项 ID，`decl`，声明名，字段列表 ID，下一表项 ID |
| `syntaxFields` | 字段列表项 ID，`cons`，字段文本 ID，下一表项 ID |
| `syntaxText` | 文本 ID，UTF-8 字节数 |
| `syntaxTextChunk` | 文本 ID，当前块的起始字节偏移，带双引号的文本块 |

每个 `syntax` 行的源码信息字段可以是 `none`，对应 `SourceInfo.none`，也可以是 `sourceInfo` 的 ID。预解析列表和字段列表的空表均写作 `0`。`syntaxArg` 中的 `0` 与元数据的语法值共用 `Syntax.missing` 语义。

一个 `syntaxTextChunk` 至多容纳 1,024 个原始字节，按 `syntaxText` 的 ID 和块偏移重组。可打印 ASCII 原样输出，双引号和反斜杠除外。其余字节均编码为 `\xhh`。解码时先拼接各块的原始字节，再按 UTF-8 解释，块边界可落在多字节字符内部。空文本有一行长度为零的 `syntaxText`，块数为零。多个子串可引用同一份全文。

## 长度和错误处理

单行缓冲区的容量为 `min(2147483647, max(16384, 4 × 文件字节数 + 4096))` 字节，其中 128 字节预留给制表符、偏移等固定字段。较大的名称、字符串或整数必须能放入该行的剩余空间。语法全文和参数数组可按块或按元素占多行。

引用越界、类型标签或结构错误、非法循环、行空间不足及 I/O 错误都会使命令返回 `2`。输出按行写入，读取方应在进程成功退出后接受整份结果。
