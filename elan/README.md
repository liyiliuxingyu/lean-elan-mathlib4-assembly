# Elan 工具链描述符

汇编实现基于 Elan v4.2.4，锁定提交
`227caca133724d5516bee25c2aeb3e609478f2d8`。实现范围是
`ToolchainDesc::from_resolved_str` 和 `ToolchainDesc::from_toolchain_dir`。
绝对路径、链接工具链名、显式远程工具链名、安装目录名的还原均由汇编处理。
无需 Rust 工具链或 C 运行库。显式工具链启动见 [RUN-PROXY.md](RUN-PROXY.md)。命令行、环境、目录覆盖、项目（包括旧式 `leanpkg.toml`）、安装目录和全局默认选择，以及相对路径和固定版本解析见 [SELECTION.md](SELECTION.md)。浮动频道解析、下载和安装仍待移植。

- [固定版本的上游实现与测试](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-dist/src/dist.rs)
- [Elan v4.2.4](https://github.com/leanprover/elan/releases/tag/v4.2.4)

## 构建和运行

在 Linux x86-64 上使用 GNU `as`、`ld` 和 `make`。

```sh
make
make test
build/elan-asm-descriptor parse leanprover/lean4:v4.3.0
build/elan-asm-descriptor parse /opt/lean
build/elan-asm-descriptor dir leanprover--lean4---v4.3.0
```

演示程序输出 `local <名称>`、`remote <仓库> <发行标签>` 或 `path <路径>`。
无效描述符退出码为 1。用法错误退出码为 2。程序检测到写入错误时退出码为 3。

## 汇编接口

函数遵循 x86-64 System V ABI。字符串以指针和字节长度传递。与上游
`&str` 对照时，输入应为 UTF-8。函数按字节处理输入。

| 函数 | 参数寄存器依次对应 | 返回值 |
| --- | --- | --- |
| `elan_parse_resolved` | 输入指针、输入长度、结果指针 | 分类编号 |
| `elan_decode_toolchain_dir` | 输入指针、输入长度、缓冲区指针、缓冲区容量 | 解码长度，容量不足时返回 `-1` |
| `elan_parse_toolchain_dir` | 输入指针、输入长度、缓冲区指针、缓冲区容量、结果指针 | 分类编号，容量不足时返回 `-1` |

结果由五个 64 位字段构成，依次为分类编号、第一段指针、第一段字节长度、第二段指针、第二段字节长度。

| 分类编号 | 分类 | 第一段 | 第二段 |
| --- | --- | --- | --- |
| 0 | 无效 | 空 | 空 |
| 1 | 链接工具链 | 名称 | 空 |
| 2 | 远程工具链 | 仓库 | 发行标签 |
| 3 | 绝对路径 | 路径 | 空 |

空字段的指针和长度均为零。解析返回的字节段引用输入区或解码缓冲区。
调用方须在使用结果期间保留对应区域。解码允许输入与缓冲区起始地址相同，
也支持二者完全分离。容量不足时，缓冲区可能已有写入，组合函数保留原结果区。
输出字节段和解码缓冲区均以显式长度使用。

## 验证记录

- `make test` 的全汇编测试通过 25 项已解析描述符测试、10 项解码测试和 2 项组合接口测试。
- 以固定提交中的正则表达式和两次替换为依据，用独立参考实现对照了 402,234 个解析输入和
  97,656 个目录名输入。另核验了 9 个 CLI 场景与退出码。对照测试未运行上游 Rust 测试。
- `readelf -d` 确认演示程序无 ELF 动态节。

许可证沿用上游的 MIT 或 Apache-2.0 双许可证，正文附于同级文件。
