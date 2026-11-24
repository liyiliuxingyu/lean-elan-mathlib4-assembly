# 从 LGZ 对象流恢复 .olean

`mathlib-lgz INPUT.lgz` 读取 leangz v0.1.15 的原始对象流，把重建的 .olean 文件写到标准输出。输入首四字节为 `LGZ!`、`LGZ1` 或 `LGZ2`。在官方的 .ltar 归档中，类型 1 成员的外层是带 leangz 字典的 Zstandard 压缩帧。解开该帧后得到这里使用的对象流。

从仓库根目录构建并读取一个已有的原始流，可以运行以下命令。

```sh
make
build/mathlib4/mathlib-lgz module.lgz > module.olean
build/mathlib4/mathlib-olean module.olean Nat.succ_injective
```

最后一个命令在该模块中查找指定声明。LGZ 工具成功时返回 0，输入、文件格式或输出错误返回 2。程序先解完整个对象流，再写出结果。

## 对象重建

| 编码 | 重建内容 |
| --- | --- |
| 普通模式 | 紧凑和扩展构造子、指针数组、字节数组、字符串、GMP 和非 GMP 大整数、thunk、task、ref、promise |
| 表达式模式 | 名称、宇宙层级和表达式构造子，连续的函数应用和常量应用，以及编码中省略的哈希、深度、标志和松散束缚变量范围 |
| 两种模式共有 | 有符号立即数、共享对象的保存和反向引用、子节点间的模式切换 |

解码器在子节点完成时写入对象，用文件头中的基地址生成序列化指针，最后回填根对象。三个可增长的临时数组分别保存待完成节点、字段和值的反向引用。大数组和深嵌套节点均由循环处理。输出缓冲区按实际产出的字节数扩展，文件头的原始大小提示不决定读取或写出范围。

`lgz_decode(input, size, out_pointer, out_length)` 遵循 Linux x86-64 System V ABI。调用方传入两个有效且各自独立的输出槽位，成功时得到匿名映射并负责调用 `munmap(*out_pointer, *out_length)`。失败返回 -1 并清空两个槽位。解码器要求输入恰好包含一个完整根对象，并检查未定义的版本标志、未保存的反向引用、输入长度及构造子尺寸。重建内容采用上游解码后的 .olean 布局。

## 验证

`make -C mathlib4 test-lgz` 使用静态测试向量并直接执行汇编程序。三个格式版本、普通对象和表达式测试的预期摘要取自官方 `leantar 0.1.15`。共享对象测试保存 65,537 个值并读取第 65,536 号槽位。另有 50,000 层单字段构造子测试，在 256 KiB 栈上逐层重建。异常用例覆盖混合对象样本的每个截断位置、越界引用、保留操作码、非法长度及尾随字节。

在 13 份 Lean v4.19.0 的 Mathlib 和 Batteries 缓存上，分别解开外层 Zstandard 帧并对原始 LGZ 流运行汇编程序。13 个 .olean 文件共 4,374,224 字节，与官方 leantar 解包结果逐字节相同。

对同一批已解开 Zstandard 帧的 13 个输入，在 Intel Xeon Platinum 8573C 上固定一个逻辑 CPU，在同一进程交替执行两版汇编解码器。160 轮计时包括分配和释放输出映射，整批重建的线程 CPU 时间中位数由 9.767 ms 降至 6.918 ms，每轮耗时之比的中位数为 1.426。改动集中在短字段复制、临时数组容量检查和按有效大小提示预分配输出。

格式依据为 leangz 提交 `c9266d97703277b680be72bc77226c2b62d1d38d`。项目中的 `zstd_dict.s` 保存该版本官方字典的 486,250 个原始字节，SHA-256 为 `83b314323c4cf64bf5199342cecaa080e0734bec5ee73edd1b2e27c040b2155b`。该字典随上游采用 Apache License 2.0 分发。

[LGZ 编解码实现](https://github.com/digama0/leangz/blob/c9266d97703277b680be72bc77226c2b62d1d38d/src/lgz.rs) · [官方字典](https://github.com/digama0/leangz/blob/c9266d97703277b680be72bc77226c2b62d1d38d/dict/v1.dict)
