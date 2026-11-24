.PHONY: test-manager test-manager-oracle

test-manager: $(BUILD_DIR)/elan $(BUILD_DIR)/elan-asm-proxy $(BUILD_DIR)/test-run-probe
	@set -eu; \
	manager="$(abspath $(BUILD_DIR))/elan"; proxy="$(abspath $(BUILD_DIR))/elan-asm-proxy"; \
	probe="$(abspath $(BUILD_DIR))/test-run-probe"; \
	base=$$(mktemp -d); trap 'chmod -R u+rwx "$$base" 2>/dev/null || :; rm -rf -- "$$base"' EXIT; \
	cd "$$base"; export ELAN_HOME="$$PWD/nested/elan home" LEAN_RECURSION_COUNT=0; \
	tc="$$ELAN_HOME/toolchains"; mkdir -p 'local root/bin' empty/bin; \
	cp "$$probe" 'local root/bin/lean'; mkdir 'empty/bin/lean'; \
	fail() { status=0; "$$manager" "$$@" > got 2> err || status=$$?; test "$$status" -eq 1; test ! -s got; test -s err; }; \
	"$$manager" toolchain list > got; printf 'no installed toolchains\n' | cmp - got; \
	test -d "$$ELAN_HOME"; test ! -e "$$tc"; \
	"$$manager" toolchain link zlocal './local root' > got 2> err; test ! -s got; test ! -s err; \
	test "$$(readlink "$$tc/zlocal")" = "$$PWD/./local root"; \
	status=0; KEEP=manager "$$proxy" lean +zlocal 'linked' > got 2> err || status=$$?; \
	test "$$status" -eq 37; test ! -s err; \
	head -n 2 got > head; printf '%s\n' "$$tc/zlocal/bin/lean" linked | cmp - head; \
	fail toolchain link zlocal ./empty; printf "error: not a file: './empty/bin/lean'\n" | cmp - err; \
	fail toolchain link zlocal missing; printf "error: not a directory: 'missing/bin'\n" | cmp - err; \
	fail toolchain link zlocal 'local root'; printf "error: 'zlocal' is already installed\n" | cmp - err; \
	test "$$(readlink "$$tc/zlocal")" = "$$PWD/./local root"; \
	"$$manager" toolchain link 'leanprover/lean4:v4.10.0' 'local root'; \
	test "$$(readlink "$$tc/leanprover--lean4---v4.10.0")" = "$$PWD/local root"; \
	for name in stable stable-test beta nightly 0.0.0-0 0.0.0-4 0.0.0 1.2.0 1.10.0 2.0.0-rc.10 2.0.0-rc.2 2.0.0; do \
		mkdir "$$tc/$$name"; done; \
	printf keep > "$$tc/stable/proof"; fail toolchain link stable 'local root'; test "$$(cat "$$tc/stable/proof")" = keep; \
	ln -s missing "$$tc/--opt--lean"; fail toolchain link '/opt/lean' 'local root'; test "$$(readlink "$$tc/--opt--lean")" = missing; \
	printf unchanged > "$$tc/junk"; fail toolchain link junk 'local root'; test "$$(cat "$$tc/junk")" = unchanged; \
	mkdir "$$tc/$$(printf '\377')"; printf 'invalid settings' > "$$ELAN_HOME/settings.toml"; \
	mkfifo "$$tc/fifo"; "$$manager" toolchain list > got; \
	printf '%s\n' 0.0.0-0 stable stable-test beta nightly /opt/lean fifo 'leanprover/lean4:v4.10.0' zlocal \
		0.0.0-4 0.0.0 1.2.0 1.10.0 2.0.0-rc.2 2.0.0-rc.10 2.0.0 | cmp - got; \
	mkdir "$$tc/bad--name"; fail toolchain list; printf "error: invalid toolchain name: 'bad/name'\n" | cmp - err; \
	rmdir "$$tc/bad--name"; \
	if test "$$(id -u)" -ne 0; then \
		chmod 555 "$$tc"; fail toolchain link denied 'local root'; test ! -L "$$tc/denied"; \
		chmod 111 "$$tc"; fail toolchain list; chmod 755 "$$tc"; \
	fi; \
	"$$manager" toolchain link winner 'local root' > r1 2>&1 & a=$$!; \
	"$$manager" toolchain link winner 'local root' > r2 2>&1 & b=$$!; \
	ra=0; rb=0; wait "$$a" || ra=$$?; wait "$$b" || rb=$$?; test "$$((ra + rb))" -eq 1; \
	test "$$(readlink "$$tc/winner")" = "$$PWD/local root"; \
	export HOME="$$PWD/fallback"; unset ELAN_HOME; "$$manager" toolchain link dev 'local root'; \
	test -L "$$HOME/.elan/toolchains/dev"; printf '%s\n' 'elan toolchain manager tests passed'

# Explicit differential against a caller-supplied official v4.2.4 executable
# named "elan". It never touches the caller's Elan home.
ELAN_ORACLE ?= elan
test-manager-oracle: $(BUILD_DIR)/elan
	@set -eu; \
	ref=$$(command -v "$(ELAN_ORACLE)"); case "$$ref" in /*) ;; *) ref="$$PWD/$$ref";; esac; \
	manager="$(abspath $(BUILD_DIR))/elan"; base=$$(mktemp -d); trap 'rm -rf -- "$$base"' EXIT; \
	cd "$$base"; export ELAN_HOME="$$PWD/home" LEAN_RECURSION_COUNT=0; \
	"$$ref" --version | grep -F 'elan 4.2.4 ' >/dev/null; \
	mkdir -p 'compiler root/bin'; touch 'compiler root/bin/lean'; \
	for bin in "$$ref" "$$manager"; do \
		if test "$$bin" = "$$ref"; then prefix=reference; else prefix=assembly; fi; \
		record() { rc=0; "$$bin" toolchain "$$@" > "$$prefix.$$1.out" 2> "$$prefix.$$1.err" || rc=$$?; \
			printf '%s\n' "$$rc" >> "$$prefix.log"; cat "$$prefix.$$1.out" "$$prefix.$$1.err" >> "$$prefix.log"; }; \
		record list; record link relative './compiler root'; record link relative 'compiler root'; \
		record link invalid 'missing root'; readlink "$$ELAN_HOME/toolchains/relative" >> "$$prefix.log"; \
		record link 'leanprover/lean4:v4.19.0' 'compiler root'; \
		ln -s missing "$$ELAN_HOME/toolchains/broken"; mkdir "$$ELAN_HOME/toolchains/1.10.0" "$$ELAN_HOME/toolchains/1.2.0"; \
		record link broken 'compiler root'; record list; mkdir "$$ELAN_HOME/toolchains/invalid name"; \
		record list; mv "$$ELAN_HOME" "$$prefix-home"; \
	done; cmp reference.log assembly.log; \
	printf '%s\n' 'elan toolchain manager upstream differential passed'
