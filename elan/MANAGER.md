# Elan 本地工具链管理

工程根目录运行 `make` 后，`build/elan/elan` 提供 Elan 4.2.4 的两个本地子命令。程序由手写 GNU 汇编构建，直接使用 Linux x86-64 系统调用。

```sh
build/elan/elan toolchain link my-build /opt/lean
build/elan/elan toolchain list
build/elan/elan-asm-proxy lean +my-build --version
```

## 链接已有编译器

`toolchain link NAME PATH` 先检查 `PATH/bin` 是目录、`PATH/bin/lean` 是普通文件，两个检查都跟随符号链接。Elan 允许链接尚未设置执行权限的普通文件。命令将工具链目录的绝对路径写入新符号链接。相对路径以实际工作目录为基准，并保留输入中的符号链接、`./` 和尾部斜杠。

目标位于 `$ELAN_HOME/toolchains`，名称中的 `/` 编码为 `--`，`:` 编码为 `---`。例如 `leanprover/lean4:v4.19.0` 对应 `leanprover--lean4---v4.19.0`。源目录验证先于目标冲突检查。重复链接已有目录、已有链接或悬空链接会失败。使用一次不可覆盖的 `symlink` 系统调用创建条目，并发创建同名链接时仅一个请求成功。预先存在的文件也会保留。成功时输出为空。

与上游相同，链接命令直接使用给定名称。某些名称可以写入磁盘，但目录名解码后不符合工具链描述符语法，会使后续列举失败。以 `-` 起首的参数可使用 `toolchain link -- NAME PATH`。

## 列举工具链

`toolchain list` 读取同一个安装目录。目录、符号链接（包括悬空链接）和其他特殊文件参与列举。普通文件和含无效 UTF-8 的目录名会被跳过。目录项类型未知时，通过已打开的目录描述符查询类型。任何参与列举的目录名无法解析时，命令报告该名称并退出，标准输出为空。

显示名称来自本项目已有的目录名解码与描述符解析。排序依据上游的语义版本键，依次比较主、次、修订版本以及预发布标识。例如 `1.2.0` 在 `1.10.0` 之前。以 `stable`、`beta`、`nightly` 起首的名称和其他非版本名称分别按上游的四种特殊预发布键排序。输出一行一个名称，空目录、缺少安装目录或安装位置为普通文件时输出 `no installed toolchains`。两个命令都不读取项目文件或全局默认设置。

## 范围与验证

设置 `ELAN_HOME` 时可使用绝对或相对目录，未设置时使用 `$HOME/.elan`。两条命令均可创建缺失的主目录，只有链接命令创建 `toolchains` 子目录。文件系统错误返回 1。路径缓冲区上限为 4095 字节。本阶段不实现管理器的其他子命令、Clap 帮助与全局选项，也不查询系统用户数据库来补全缺失的 `HOME`。用法错误和不常见的系统错误可能采用不同于官方 CLI 的诊断文字。

`make -C elan test` 在临时目录中验证链接、列举和代理实际启动，覆盖并发竞争、文件类型、错误诊断、权限和语义版本排序。具有写保护特权的 root 运行测试时会跳过权限拒绝用例。另有可复跑的官方程序对照目标。参数指向名为 `elan` 的 4.2.4 官方程序。

```sh
make -C elan test-manager-oracle ELAN_ORACLE=/absolute/path/to/elan
```

开发时用固定版本的官方 Linux 二进制完成了 65 个场景对照，两边的退出状态、标准输出、标准错误和测试目录状态相同。排序场景含 1548 个不同名称，覆盖无符号 64 位边界、预发布混合标识和跨多次目录读取的输入。

[上游子命令](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-cli/elan_mode.rs) · [安装目录列举](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/config.rs) · [本地安装验证](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/toolchain.rs) · [排序规则](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-utils/src/utils.rs)
