# Mathlib 的自然数配对函数

`mathlib-pairing` 用 x86-64 Linux 汇编实现 Mathlib4 v4.19.0 的 `Nat.pair` 和 `Nat.unpair`。输入是无符号十进制整数，允许前导零。每个结果单独占一行，两个坐标之间用空格分隔。

```sh
make -C mathlib4
mathlib4/build/mathlib-pairing pair 42 13      # 1819
mathlib4/build/mathlib-pairing unpair 1819    # 42 13
mathlib4/build/mathlib-pairing pair 18446744073709551616 18446744073709551616
# 340282366920938463500268095579187314688
```

输入、中间结果和输出都用变长整数表示，每个存储单元保存八位十进制数。程序按输入长度分配空间，实际输入大小受 Linux 单个命令行参数长度和可用内存限制。两种运算最坏情况下的时间均与输入位数的平方成正比，额外空间与输入位数成正比。可执行文件使用 Linux 系统调用分配内存和输出结果。

## 两个坐标怎样对应一个自然数

当 `a < b` 时，编码为 `b² + a`。当 `b ≤ a` 时，编码为 `a² + a + b`。因此从 `s²` 到 `(s+1)²−1` 的编码恰好对应较大坐标为 `s` 的所有有序对。解码时求出 `s = floor(√n)` 与 `r = n−s²`。若 `r < s`，返回 `(r,s)`，否则返回 `(s,r−s)`。[Mathlib v4.19.0 的函数定义](https://github.com/leanprover-community/mathlib4/blob/v4.19.0/Mathlib/Data/Nat/Pairing.lean#L33-L44)

汇编从高位到低位逐组开平方。对已读入的数值前缀 `P`，保持 `P = s² + r` 且 `0 ≤ r < 2s+1`。设 `B = 10000`，读入下一组八位十进制数字 `g` 后，取 `R = B²r + g`。二分搜索满足 `(2Bs+x)x ≤ R` 的最大数字 `0 ≤ x < B`。由 `(Bs+x)²` 的展开式，新的整数平方根和余数分别为 `Bs+x` 和 `R−(2Bs+x)x`。上游依赖 Batteries 使用牛顿迭代计算 `Nat.sqrt`。[锁定版本的 Batteries 源码](https://github.com/leanprover-community/batteries/blob/f5d04a9c4973d401c8c92500711518f7c656f034/Batteries/Data/Nat/Basic.lean)

## 核对汇编输出

基础测试覆盖 26 组三元组、前导零、参数数量及无效数字。最大的固定输入含 200 位十进制数。另有 924 个命令行样例，用官方 Lean 4.19.0 执行从上游提取的三个函数定义，逐字节比较标准输出。样例包括完全平方数附近的编码、两个分支的交界点和独立生成的解码输入。参考定义及测试数据只链接到测试或用于生成测试输入。

```sh
make -C mathlib4 test-pairing
make -C mathlib4 test-pairing-lean LEAN=/path/to/lean-4.19.0/bin/lean
```

发布缓存提供了与自带参考定义相独立的检验。下列命令取出 Mathlib 编译器生成的 `Pairing.c` 和 Batteries 的 `Basic.c`，验证归档与源码的 SHA-256，原样编译这两个文件并链接官方 Lean 4.19.0 运行库。对汇编输出构成的 924 组 `(a,b,n)`，分别调用发布版本的 `Nat.pair` 验证 `n`、调用 `Nat.unpair` 验证两个坐标，共完成 1,848 次对照。

```sh
cache=$(mktemp -d)
for key in 836f4072582cbc3e 7e7ccbecb541d1d5; do
    curl -fLsS "https://lakecache.blob.core.windows.net/mathlib4/f/$key.ltar" -o "$cache/$key.ltar" || exit 1
done
make -C mathlib4 test-pairing-published \
    PAIRING_ARCHIVES="$cache" LEAN=/path/to/lean-4.19.0/bin/lean
```

若已安装完整 Mathlib v4.19.0，也可以在该项目可用的 Lean 搜索路径下运行 `test-pairing-mathlib`，直接导入 `Mathlib.Data.Nat.Pairing` 后执行同一批样例。上游模块给出了通用逆函数定理 `Nat.unpair_pair` 和 `Nat.pair_unpair`。本项目的测试验证汇编可执行文件在所列样例上的计算结果。
