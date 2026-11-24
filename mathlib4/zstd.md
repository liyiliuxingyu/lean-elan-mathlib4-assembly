# 在内存里读取归档成员的 Zstandard 帧

`mathlib-ltar` 读取普通压缩成员和 LGZ 成员时都经过这层。普通成员在 Zstandard 解码完成后得到原文件字节。按 leangz v0.1.15 构建的 LGZ 成员先使用上游的 `dict/v1.dict` 解开 Zstandard 帧，再由 LGZ 解码器重建 Lean 对象。生产程序直接使用 Linux x86-64 汇编实现，只在可选的对照测试中链接系统的 `libzstd`。

## 接口

以下函数使用 System V AMD64 调用约定。缓冲区由调用方保证可读或可写，输入、输出和结果参数各自独立。结构体中的字段都是 64 位无符号整数，字节偏移可通过 [zstd.inc](zstd.inc) 中的符号取得。

| 函数 | 返回的结果 |
| --- | --- |
| `asm_zstd_inspect(src, len, info)` | 检查一个普通帧的文件头、所有块边界及可选校验字段的范围。返回首帧消耗的字节数、头长、字典 ID、窗口、声明的输出大小、标志、三种块的数量和 raw/RLE 块的总输出长度。首帧之后可以有其他字节。 |
| `asm_zstd_next_block(src, len, &offset, entry)` | 从已检查帧的 `header_bytes` 开始逐块调用。每次得到数据区偏移、存储长度、块头声明的长度、类型及末块标记，并前移 `offset`。见到末块即停止。 |
| `asm_zstd_decode(src, len, dst, capacity, &written)` | 使用调用方提供的缓冲区、无字典解开首帧。失败时 `written` 为零。成功后即可使用输出。 |
| `asm_zstd_decode_dict_alloc(src, len, dict, dictlen, &out, &written)` | 归档读取器使用的单帧解码入口。要求输入恰好包含一个普通帧，接受空字典、至少 8 字节的原始历史字典或格式化字典。成功后用 `munmap(out, max(1, written))` 释放输出。失败时指针和长度均为零。 |

标志的第 0、1、2 位依次表示帧中声明了内容长度、带内容校验、单段帧。长度缺失时 `content_size` 字段为 `UINT64_MAX`。单段帧的窗口等于内容长度，其他帧从窗口描述字节计算窗口。块类型 0、1、2 依次表示 raw、RLE 和 compressed。RLE 的存储长度总是一字节，块头大小给出重复次数。目录函数只检查结构。解码函数另外检查熵表、匹配距离、实际输出长度和可选的 XXH64 低 32 位校验值。

状态 0 表示成功，1 表示帧结构、压缩数据或字典结构错误，2 表示帧指定的字典 ID 缺失或不匹配，4 表示目标缓冲区不足，5 表示校验失败，6 表示系统无法分配内存。状态 3 保留。`asm_zstd_decode_dict_alloc` 和可选的单帧对照程序 `zstd-oracle` 都要求输入恰含一个普通帧。归档层另行遍历拼接帧，依次合并普通帧的输出并跳过 skippable frame，详见 [归档读取说明](LTAR.md)。

## 边界与验证

解码器支持三种普通数据块、四种 literals 编码、单路与四路 Huffman、四种序列编码模式、跨块重复表和重复匹配距离。内容长度缺失时，以 raw/RLE 实际输出长度加上每个压缩块最多 `min(window, 128 KiB)` 计算映射上界。实际只写解码出的字节，最后释放多映射的完整页。每个包含压缩块的帧另用 160 KiB 工作区存放解码状态和当前块的 literals。全程使用调用独立的状态。

从项目根目录运行下面的命令。第一条只需 GNU 汇编器、链接器和 Linux。第二条另需 C 链接驱动、系统 libzstd 开发包和本地缓存目录。它从真实归档逐一切出普通和 LGZ 成员，比较两套实现读取的帧头、压缩长度及解码后的全部字节。

```sh
make -C mathlib4 test-zstd
make -C mathlib4 test-zstd-oracle ZSTD_ARCHIVES=/path/to/mathlib/cache
```

内置回归测试包含真实缓存 `049953d176d7bde9.ltar` 中 `Batteries/Tactic/Lint.ilean` 的 66 字节压缩帧。该帧没有声明内容长度，使用 8 MiB 窗口，解开后为 62 字节 JSON。另一次对照涵盖 13 个官方缓存的 39 个帧、70 个压缩块，共 2,273,280 字节输出，其中 13 个 LGZ 外层帧使用字典 ID `1598502866`。

格式和归档约定分别见 [RFC 8878](https://www.rfc-editor.org/rfc/rfc8878.html) 和 [leangz v0.1.15 的 LTAR 实现](https://github.com/digama0/leangz/blob/c9266d97703277b680be72bc77226c2b62d1d38d/src/ltar.rs)。
