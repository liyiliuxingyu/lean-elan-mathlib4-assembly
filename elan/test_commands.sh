#!/bin/sh
# SPDX-License-Identifier: MIT OR Apache-2.0
# Build/test harness only. No installed Elan, Lean, Rust, or network required.
set -eu
manager=$1
probe=$2
oracle=${3:-}
base=$(mktemp -d)
trap 'rm -rf -- "$base"' EXIT
cd "$base"
base=$PWD
export ELAN_HOME="$base/elan home" KEEP=commands LEAN_RECURSION_COUNT=0
unset ELAN_TOOLCHAIN ELAN_NO_OVERRIDE_NOTICE RUST_BACKTRACE
root="$base/compiler root"
tc="$ELAN_HOME/toolchains"
project="$base/project"
sub="$project/sub"
orig_path=/usr/bin:/bin
mkdir -p "$root/bin/up" "$root/bin/UP" "$sub" "$base/external"
for file in lean 'Mixed.Ext' 'up/tool' 'UP/Tool.Ext' é ας ασα 'i̇' '.hidden' '--help'; do
    cp "$probe" "$root/bin/$file"
done
touch "$root/bin/no-exec"
ln -s lean "$root/bin/alias"
ln -s absent "$root/bin/broken"
cp "$probe" "$base/external/PATHtool"

record() {
    expected=$1
    shift
    actual=0
    "$bin" "$@" >"$base/out" 2>"$base/err" || actual=$?
    if test "$expected" -ne "$actual"; then
        printf '%s returned %s, expected %s\n' "$*" "$actual" "$expected" >&2
        cat "$base/err" >&2
        exit 1
    fi
    # Explicit byte lengths distinguish empty output and stdout/stderr boundaries.
    printf 'rc=%s out=%s err=%s\n' "$actual" "$(wc -c < "$base/out")" "$(wc -c < "$base/err")" >> "$log"
    cat "$base/out" "$base/err" >> "$log"
    n=$((n+1))
}
which_is() {
    spelling=$1
    shift
    record 0 which "$@"
    printf '%s\n' "$spelling" | cmp - "$base/out"
    test ! -s "$base/err"
}
child() {
    arg0=$1
    resolved=$2
    shift 2
    record 37 run "$@"
    printf '%s\n' "$arg0" 'one argument' '' '+later' '--install' '--help' \
        KEEP=commands "ELAN_HOME=$ELAN_HOME" "ELAN_TOOLCHAIN=$resolved" \
        "LEAN_RECURSION_COUNT=$child_count" "PATH=$ELAN_HOME/bin:$PATH" | cmp - "$base/out"
    test ! -s "$base/err"
}
run_suite() {
    bin=$1
    log=$2
    n=0
    cd "$sub"
    export PATH=$orig_path LEAN_RECURSION_COUNT=0
    unset ELAN_TOOLCHAIN
    # Exercise first-use settings and project-root registration before installation.
    printf '%s\n' "$root" > "$project/lean-toolchain"
    record 0 which LEAN
    printf '%s\n' "$root/bin/lean" | cmp - "$base/out"
    printf "warning: could not canonicalize path: '%s'\n" "$tc" | cmp - "$base/err"
    printf 'telemetry = false\nversion = "12"\n\n[overrides]\n' | cmp - "$ELAN_HOME/settings.toml"
    printf %s "$project" | cmp - "$ELAN_HOME/known-projects"
    mkdir -p "$tc" "$ELAN_HOME/bin"
    cp "$probe" "$ELAN_HOME/bin/HOMEtool"
    ln -s "$root" "$tc/dev"
    ln -s "$root" "$tc/default"
    ln -s absent "$tc/dangling"
    installed="$tc/leanprover--lean4---v4.19.0"
    mkdir -p "$installed/bin"
    cp "$probe" "$installed/bin/lean"
    printf '4.19.0\n' > "$sub/lean-toolchain"
    which_is "$installed/bin/lean" lean
    which_is "$installed/bin/lean" LeAn
    printf '%s\n%s' "$project" "$sub" | cmp - "$ELAN_HOME/known-projects"
    rm "$sub/lean-toolchain"
    printf 'version = "12"\ndefault_toolchain = "default"\n[overrides]\n"%s" = "dev"\n' "$sub" >"$ELAN_HOME/settings.toml"
    which_is "$tc/dev/bin/lean" lean
    printf 'version = "12"\ndefault_toolchain = "default"\n[overrides]\n' > "$ELAN_HOME/settings.toml"
    rm "$project/lean-toolchain"
    which_is "$tc/default/bin/lean" lean
    printf '[package]\nlean_version = "dev"\n' > "$project/leanpkg.toml"
    which_is "$tc/dev/bin/lean" lean
    rm "$project/leanpkg.toml"
    cd "$installed/bin"
    which_is "$installed/bin/lean" lean
    cd "$sub"
    export ELAN_TOOLCHAIN=dev
    for pair in 'LEAN:lean' 'Mixed.Ext:Mixed.Ext' 'UP/TOOL:up/tool' 'UP/Tool.Ext:UP/Tool.Ext' \
        'É:é' 'ΑΣ:ας' 'ΑΣΑ:ασα' 'İ:i̇' '.HIDDEN:.hidden' '--help:--help' 'alias:alias' 'no-exec:no-exec'; do
        which_is "$tc/dev/bin/${pair#*:}" -- "${pair%%:*}"
    done
    which_is /bin/sh /bin/sh
    for missing in missing broken .. '' 'UP/' 'Mixed.Ext/.'; do
        record 1 which -- "$missing"
        test ! -s "$base/out"
        grep -F 'error: not a file:' "$base/err" >/dev/null
    done
    record 0 which --help
    record 1 which --toolchain dev lean
    record 1 which lean extra
    record 1 which
    record 0 run --help
    record 1 run
    record 1 run dev
    record 1 run --install --install dev lean
    child_count=1
    export PATH="$base/external:$orig_path"
    set -- 'one argument' '' '+later' '--install' '--help'
    child "$tc/dev/bin/lean" dev dev LEAN "$@"
    child "$installed/bin/lean" leanprover/lean4:v4.19.0 --install 4.19.0 lean "$@"
    child "$root/bin/lean" "$root" "$root" --install lean "$@"
    child "$tc/dev/bin/--help" dev dev -- --help "$@"
    child HOMEtool dev dev HOMEtool "$@"
    child PATHtool dev dev PATHtool "$@"
    child "$base/external/PATHtool" dev dev "$base/external/PATHtool" "$@"
    child PATHtool dangling dangling PATHtool "$@"
    export LEAN_RECURSION_COUNT=-2
    child_count=-1
    child PATHtool dev dev PATHtool "$@"
    export LEAN_RECURSION_COUNT=5
    child_count=6
    child "$tc/dev/bin/lean" dev dev lean "$@"
    record 1 run dev PATHtool
    grep -F "does not have the binary" "$base/err" >/dev/null
    export LEAN_RECURSION_COUNT=0
    for cmd in no-exec missing ''; do
        record 1 run dev -- "$cmd"
        grep -F 'error: command failed:' "$base/err" >/dev/null
    done
    record 1 run './missing' lean
    record 1 run 'a/b' lean
    # Changing the toolchain through run did not rewrite project metadata.
    printf '%s\n%s' "$project" "$sub" | cmp - "$ELAN_HOME/known-projects"
    printf '%s\n' "$n" > "$base/count"
}
if test -n "$oracle"; then
    "$oracle" --version | grep -F 'elan 4.2.4 ' >/dev/null
    run_suite "$oracle" "$base/reference"
    mv "$ELAN_HOME" "$base/reference home"
fi
run_suite "$manager" "$base/assembly"
if test -n "$oracle"; then
    cmp "$base/reference" "$base/assembly"
    printf 'elan which/run upstream differential passed (%s cases)\n' "$(cat "$base/count")"
else
    printf 'elan which/run tests passed (%s cases)\n' "$(cat "$base/count")"
fi
