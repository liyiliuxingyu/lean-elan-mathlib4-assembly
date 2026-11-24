# Elan 本地工具链管理

工程根目录运行 `make` 后，`build/elan/elan` 提供 Elan 4.2.4 的本地工具链链接、列举、命令定位和启动功能。程序由手写 GNU 汇编构建，直接使用 Linux x86-64 系统调用。

```sh
build/elan/elan toolchain link my-build /opt/lean
build/elan/elan toolchain list
ELAN_TOOLCHAIN=my-build build/elan/elan which lean
build/elan/elan run my-build lean --version
```

## 链接已有编译器

`toolchain link NAME PATH` 先检查 `PATH/bin` 是目录、`PATH/bin/lean` 是普通文件，两个检查都跟随符号链接。Elan 允许链接尚未设置执行权限的普通文件。命令将工具链目录的绝对路径写入新符号链接。相对路径以实际工作目录为基准，并保留输入中的符号链接、`./` 和尾部斜杠。

目标位于 `$ELAN_HOME/toolchains`，名称中的 `/` 编码为 `--`，`:` 编码为 `---`。例如 `leanprover/lean4:v4.19.0` 对应 `leanprover--lean4---v4.19.0`。源目录验证先于目标冲突检查。重复链接已有目录、已有链接或悬空链接会失败。使用一次不可覆盖的 `symlink` 系统调用创建条目，并发创建同名链接时仅一个请求成功。预先存在的文件也会保留。成功时输出为空。

与上游相同，链接命令直接使用给定名称。某些名称可以写入磁盘，但目录名解码后不符合工具链描述符语法，会使后续列举失败。以 `-` 起首的参数可使用 `toolchain link -- NAME PATH`。

## 列举工具链

`toolchain list` 读取同一个安装目录。目录、符号链接（包括悬空链接）和其他特殊文件参与列举。普通文件和含无效 UTF-8 的目录名会被跳过。目录项类型未知时，通过已打开的目录描述符查询类型。任何参与列举的目录名无法解析时，命令报告该名称并退出，标准输出为空。

显示名称来自本项目已有的目录名解码与描述符解析。排序依据上游的语义版本键，依次比较主、次、修订版本以及预发布标识。例如 `1.2.0` 在 `1.10.0` 之前。以 `stable`、`beta`、`nightly` 起首的名称和其他非版本名称分别按上游的四种特殊预发布键排序。输出一行一个名称，空目录、缺少安装目录或安装位置为普通文件时输出 `no installed toolchains`。链接和列举命令都不读取项目文件或全局默认设置。

## 定位和运行命令

`elan which COMMAND` 按环境、目录覆盖、项目文件、安装目录和全局默认设置选择工具链，返回相应文件的路径。目录查找顺序和设置格式见 [SELECTION.md](SELECTION.md)。Elan 4.2.4 的 `which` 没有 `--toolchain` 选项。可用 `ELAN_TOOLCHAIN=my-build elan which lean` 指定工具链。返回的路径保留符号链接和原有的相对路径分量，文件只需是普通文件。命令缺失时输出相关路径，返回 1。

对于目录覆盖，`which` 按管理器规则静默选择。首次需要读取默认设置时，程序会建立 `settings.toml`。从 `lean-toolchain` 找到有效描述符后，也会将该文件所在目录登记到 `$ELAN_HOME/known-projects`。同一个项目只登记一次。来自环境、`leanpkg.toml` 或全局默认的选择不会添加登记。

`elan run [--install] TOOLCHAIN COMMAND [ARG ...]` 使用显式工具链并配置环境。对于已经安装或链接的工具链，加上 `--install` 的效果与官方程序一致。命令支持绝对路径、含斜杠的相对路径和普通名称。若文件名末段带扩展名，保留整个输入拼写。末段无扩展名时，对整个命令路径执行 Unicode 17.0 默认小写转换，包括希腊大写 Sigma 的上下文规则和 `İ` 的多字符映射。

程序先尝试工具链的 `bin` 目录。候选路径对应普通文件时直接执行，文件不可执行会报告权限错误。若候选文件缺失，`run` 使用原始命令拼写，通过更新后的 `PATH` 查找外部程序或直接执行含斜杠的路径。它将 `$ELAN_HOME/bin` 加到环境路径开头，设置 `ELAN_TOOLCHAIN`、`ELAN_HOME` 并更新 `LEAN_RECURSION_COUNT`。递归计数已到 5 时，命令缺失会触发上游的递归保护。成功启动由 `execve` 替换进程，子进程的参数、标准流、工作目录和退出状态均可直接使用。

## 范围与验证

设置 `ELAN_HOME` 时可使用绝对或相对目录，未设置时使用 `$HOME/.elan`。管理器会按需创建缺失的主目录，链接命令还可创建 `toolchains` 子目录。文件系统错误返回 1。路径缓冲区上限为 4095 字节。本阶段支持 `which --help` 和 `run --help`。其余管理器子命令、通用 Clap 接口和全局选项仍待实现。程序也不查询系统用户数据库来补全缺失的 `HOME`。浮动频道元数据、离线频道缓存和缺失工具链的远程安装都未实现。部分命令行、配置和系统错误使用简化的诊断。对于缺少默认工具链的 `which` 及无效 UTF-8 命令参数，保留官方程序的退出码 101，输出简短错误。

`make -C elan test` 在临时目录中验证链接、列举和代理实际启动，覆盖并发竞争、文件类型、错误诊断、权限和语义版本排序。具有写保护特权的 root 运行测试时会跳过权限拒绝用例。另有可复跑的官方程序对照目标。参数指向名为 `elan` 的 4.2.4 官方程序。

```sh
make -C elan test-manager-oracle test-commands-oracle ELAN_ORACLE=/absolute/path/to/elan
```

`test-commands-oracle` 在临时目录中执行 50 个 `which` 和 `run` 场景，逐项核对退出状态、标准输出和标准错误，并检查生成的设置和项目登记内容。日常 `make test` 会用相同的固定样例和独立期望值验证，无需安装 Elan。本阶段另用 150 个输入比较官方程序，并通过 `run` 调用官方 Lean 4.19.0 编译了一份定理文件。

此前用固定版本的官方 Linux 二进制完成了链接和列举的 65 个场景对照，两边的退出状态、标准输出、标准错误和测试目录状态相同。排序场景含 1548 个不同名称，覆盖无符号 64 位边界、预发布混合标识和跨多次目录读取的输入。

[上游子命令](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-cli/elan_mode.rs) · [安装目录列举](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/config.rs) · [本地安装验证](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/toolchain.rs) · [排序规则](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-utils/src/utils.rs)
