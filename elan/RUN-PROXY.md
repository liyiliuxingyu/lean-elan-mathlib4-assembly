# Elan 已安装工具链启动器

`elan-asm-run` 用 Linux x86-64 汇编启动已选定的本地工具链。它复用描述符解析器，按 Elan v4.2.4 的目录映射规则定位 `bin` 中的命令，设置子进程环境，并用 `execve` 替换当前进程。传给命令的参数、已继承的文件描述符和成功启动后的退出状态由 Linux 原样处理。

从工程根目录运行 `make` 后，启动器位于 `build/elan/elan-asm-run`。

```sh
build/elan/elan-asm-run /opt/lean lean --version
build/elan/elan-asm-run my-linked-lean lake build
build/elan/elan-asm-run leanprover/lean4:v4.19.0 lean --version
```

- 绝对路径直接用作工具链根目录。已链接的本地名称及完整远程发行描述符定位到 `ELAN_HOME/toolchains`。例如 `leanprover/lean4:v4.19.0` 对应目录名 `leanprover--lean4---v4.19.0`。
- 设置了 `ELAN_HOME` 时使用该值，相对值以当前目录为基准。否则使用 `$HOME/.elan`。运行时将 `ELAN_HOME` 和当前描述符写入子进程环境，按上游规则递增 `LEAN_RECURSION_COUNT` 并把 `ELAN_HOME/bin` 加入 `PATH` 开头。`ELAN_HOME` 含有冒号时按上游规则保留原 `PATH`。
- 命令为 `bin` 下的单个文件名。无扩展名时转换 ASCII 大写字母。有扩展名时保留原拼写。
- 参数或配置错误返回 `2`。内核报告命令路径不存在或中间组件不是目录时返回 `127`。其余启动错误返回 `126`。启动成功后直接返回目标进程的状态。

该入口处理已解析、已安装工具链的正常启动路径。项目默认和覆盖选择、相对工具链路径、远程渠道解析、下载、安装、系统 `PATH` 查找回退以及无扩展名时的 Unicode 小写转换仍待移植。工具链命令本身使用其原有实现。

[Elan v4.2.4 工具链目录和环境处理](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/toolchain.rs#L388) · [Unix 进程启动实现](https://github.com/leanprover/elan/blob/227caca133724d5516bee25c2aeb3e609478f2d8/src/elan/command.rs)

## 验证

`make -C elan test` 使用汇编测试程序检查绝对路径和已安装发行描述符，核对转发参数及环境，确认目标进程退出码和命令缺失诊断。另执行了 26 项本地启动检查，其中 16 项与官方 Elan 4.2.4 二进制的输出和退出码逐项一致。还用该启动器从 Linux 发行包启动了 Lean 4.19.0 的 `lean --version`。

`readelf -d` 确认启动器无动态节。构建只使用 GNU `as` 和 `ld`。
