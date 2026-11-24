# Elan 本地工具链选择

`elan-asm-proxy COMMAND [+TOOLCHAIN] [ARG ...]` 从已有工具链中选出一个，再通过 Linux 的 `execve` 启动其中的命令。实现使用 GNU 汇编，复用本项目的 Elan 描述符解析、进程启动和 Lean UTF-8 代码。构建入口在工程根目录。

```sh
make
build/elan/elan-asm-proxy lean --version
build/elan/elan-asm-proxy lean +leanprover/lean4:v4.19.0 --version
ELAN_TOOLCHAIN=/opt/lean build/elan/elan-asm-proxy lake build
```

| 优先级 | 工具链来源 | 读取方式 |
| --- | --- | --- |
| 1 | 命令名之后的首个参数 `+TOOLCHAIN` | 去掉加号，余下参数逐个传给工具链命令。位于其他位置的加号参数照常转发。 |
| 2 | `ELAN_TOOLCHAIN` | 使用非空、有效 UTF-8 的值。 |
| 3 | 同级目录覆盖、`lean-toolchain`、`leanpkg.toml` | 从实际工作目录逐级向上。每一级先匹配 `[overrides]` 中的目录，再检查 `lean-toolchain`，最后读取 `leanpkg.toml` 的 `[package].lean_version`。文件可为指向普通文件的符号链接。 |
| 4 | 已安装工具链目录 | 每一级即将上溯时，若该目录是 `$ELAN_HOME/toolchains` 的直接子目录，解码目录名并使用对应的已安装工具链。 |
| 5 | `settings.toml` 的 `default_toolchain` | 从 `$ELAN_HOME/settings.toml` 读取。未设置 `ELAN_HOME` 时使用 `$HOME/.elan`。 |

命令行和环境都无工具链时，程序先读取设置并校验格式，再遍历项目目录。设置文件缺失时仍可使用项目文件。例如，子目录中的项目文件优先于父目录的数据库覆盖，而同级的数据库覆盖优先于项目文件。命中数据库覆盖时输出 Elan 的两行提示，设置 `ELAN_NO_OVERRIDE_NOTICE` 可抑制提示。数据库中保存的值为已解析描述符。`lean-toolchain` 仅使用首行，去掉首尾 Unicode 空白。空首行或无效文本引发错误。`leanpkg.toml` 缺少 `lean_version` 时继续查找。查找过程只读，成功启动后沿用原启动器的环境和退出状态规则。

**描述符解析。** 先检查输入指定的目录中是否有普通文件 `bin/lean`。`lean-toolchain` 中的相对路径以文件所在目录为基准。`leanpkg.toml`、命令行、环境和全局默认中的相对路径以进程当前目录为基准。之后查找 `$ELAN_HOME/toolchains` 中与发行名同名的工具链符号链接。存在时采用链接名。最后处理固定版本，裸版本使用默认仓库 `leanprover/lean4`，数字开头的版本加上 `v`。例如 `4.19.0` 选中 `leanprover/lean4:v4.19.0`。以 `nightly` 开头的固定发行名使用以 `-nightly` 结尾的仓库名。

**设置文件。** 支持 Elan 4.2.4 生成的常见格式，包括版本 `"2"` 或 `"12"`、字符串 `default_toolchain`、布尔值 `telemetry` 和可选的末尾表 `[overrides]`，其中最多可存放 2,048 组目录和已解析工具链。接受 LF、CRLF、行注释、单引号和双引号字符串、简单转义以及 `\u`、`\U` Unicode 标量转义。无效描述符、重复的键、未知顶层字段和其他未实现的 TOML 用法会报错。设置文件和项目文件各限 65,536 字节，必须是无内嵌 NUL 的 UTF-8。路径上限为 4,095 字节。

**旧式项目清单。** `leanpkg.toml` 支持单层命名表、普通键或引号键、字符串、十进制有符号 64 位整数和布尔值。单行内联表可描述常见的 git、rev 和 path 依赖，也支持内联的 `package` 表。最多处理 2,048 个键和表头，不支持数组、多行字符串、点分键、嵌套表和其他 TOML 标量类型。超出此范围或存在重复键时返回配置错误。

此独立代理只读配置。管理器的 [elan which](MANAGER.md) 已实现初始设置文件和项目垃圾回收登记。浮动频道解析、联网下载和安装仍待移植。配置错误或缺少选择时返回 2，工具链命令缺失时返回 127。子进程启动细节见 [RUN-PROXY.md](RUN-PROXY.md)。

## 验证

`make -C elan test` 在临时目录中用汇编子进程核对选择优先级、实际执行文件、参数、环境与退出状态，并运行设置解析用例。与官方 Elan 4.2.4 代理的额外对照覆盖 138 次成功启动，两边的标准输出、标准错误和退出状态逐项相同。另有 12 个无效输入被双方拒绝。另用父目录的 `lean-toolchain` 选中官方 Lean 4.19.0，从子目录编译了一份含定理的 Lean 源文件并生成 `.olean`。

上游固定提交为 `227caca133724d5516bee25c2aeb3e609478f2d8`。[命令行优先级](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan-cli/proxy_mode.rs) · [目录遍历](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/config.rs) · [路径和发行名解析](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/toolchain.rs) · [设置格式](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/settings.rs)
