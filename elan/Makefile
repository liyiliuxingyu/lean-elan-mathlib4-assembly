BUILD_DIR ?= build

.PHONY: all test test-run-proxy test-selection clean
all: $(BUILD_DIR)/elan-asm-descriptor $(BUILD_DIR)/elan-asm-run $(BUILD_DIR)/elan-asm-proxy

test: all $(BUILD_DIR)/test-toolchain-desc $(BUILD_DIR)/test-settings-default test-run-proxy test-selection
	$(BUILD_DIR)/test-settings-default
	$(BUILD_DIR)/test-toolchain-desc

test-run-proxy: $(BUILD_DIR)/elan-asm-run $(BUILD_DIR)/test-run-probe
	@set -eu; \
	scratch=$$(mktemp -d); \
	trap 'rm -rf -- "$$scratch"' EXIT; \
	scratch=$$(cd "$$scratch" && pwd); \
	home="$$scratch/elan home"; root="$$scratch/toolchain root"; \
	name=leanprover/lean4:v4.19.0; installed="$$home/toolchains/leanprover--lean4---v4.19.0"; \
	mkdir -p "$$root/bin" "$$installed/bin"; \
	cp "$(BUILD_DIR)/test-run-probe" "$$root/bin/lean"; \
	cp "$(BUILD_DIR)/test-run-probe" "$$installed/bin/lean"; \
	for descriptor in "$$root" "$$name"; do \
		target="$$root"; \
		if test "$$descriptor" = "$$name"; then target="$$installed"; fi; \
		status=0; \
		ELAN_HOME="$$home" ELAN_TOOLCHAIN=old LEAN_RECURSION_COUNT=+2 PATH=/p KEEP=verbatim \
			"$(BUILD_DIR)/elan-asm-run" "$$descriptor" LEAN 'one argument' '' > "$$scratch/actual" || status=$$?; \
		test "$$status" -eq 37; \
		printf '%s\n' "$$target/bin/lean" 'one argument' '' 'KEEP=verbatim' \
			"ELAN_HOME=$$home" "ELAN_TOOLCHAIN=$$descriptor" 'LEAN_RECURSION_COUNT=3' \
			"PATH=$$home/bin:/p" | cmp - "$$scratch/actual"; \
	done; \
	status=0; \
	ELAN_HOME="$$home" LEAN_RECURSION_COUNT=0 "$(BUILD_DIR)/elan-asm-run" "$$root" missed \
		> "$$scratch/actual" 2> "$$scratch/diagnostic" || status=$$?; \
	test "$$status" -eq 127; test ! -s "$$scratch/actual"; test -s "$$scratch/diagnostic"; \
	printf '%s\n' 'elan local launcher tests passed'

$(BUILD_DIR)/elan-asm-descriptor: $(BUILD_DIR)/descriptor_cli.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/elan-asm-run: $(BUILD_DIR)/run_proxy.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/proxy_entry.o: run_proxy.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) --defsym AUTO_SELECT=1 -o $@ $<

$(BUILD_DIR)/selection_utf8.o: ../lean4/utf8.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o $@ $<

$(BUILD_DIR)/elan-asm-proxy: $(BUILD_DIR)/proxy_entry.o $(BUILD_DIR)/select_toolchain.o $(BUILD_DIR)/leanpkg_version.o $(BUILD_DIR)/settings_default.o $(BUILD_DIR)/toolchain_desc.o $(BUILD_DIR)/selection_utf8.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/test-settings-default: $(BUILD_DIR)/test_settings_default.o $(BUILD_DIR)/settings_default.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/test-toolchain-desc: $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/test-run-probe: $(BUILD_DIR)/test_run_probe.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

clean:
	$(RM) $(BUILD_DIR)/test-settings-default $(BUILD_DIR)/test_settings_default.o
	$(RM) $(BUILD_DIR)/elan-asm-proxy $(BUILD_DIR)/proxy_entry.o $(BUILD_DIR)/select_toolchain.o
	$(RM) $(BUILD_DIR)/leanpkg_version.o $(BUILD_DIR)/settings_default.o $(BUILD_DIR)/selection_utf8.o
	$(RM) $(BUILD_DIR)/elan-asm-run $(BUILD_DIR)/run_proxy.o
	$(RM) $(BUILD_DIR)/test-run-probe $(BUILD_DIR)/test_run_probe.o
	rm -f $(BUILD_DIR)/elan-asm-descriptor $(BUILD_DIR)/test-toolchain-desc
	rm -f $(BUILD_DIR)/descriptor_cli.o $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o

test-selection: $(BUILD_DIR)/elan-asm-proxy $(BUILD_DIR)/test-run-probe
	@set -eu; \
	proxy="$(abspath $(BUILD_DIR))/elan-asm-proxy"; probe="$(abspath $(BUILD_DIR))/test-run-probe"; \
	base=$$(mktemp -d); trap 'rm -rf -- "$$base"' EXIT; base=$$(cd "$$base" && pwd); \
	root="$$base/toolchain root"; project="$$base/project"; home="$$base/home"; \
	mkdir -p "$$root/bin" "$$project/sub/child" "$$home/toolchains"; \
	cp "$$probe" "$$root/bin/lean"; \
	for name in cli env project default; do ln -s "$$root" "$$home/toolchains/$$name"; done; \
	pinned='leanprover/lean4:v4.19.0'; installed="$$home/toolchains/leanprover--lean4---v4.19.0"; \
	mkdir -p "$$installed/bin"; cp "$$probe" "$$installed/bin/lean"; \
	printf '%s\n' 'version = "12"' 'default_toolchain = "default"' '[overrides]' > "$$home/settings.toml"; \
	printf '  project\r\nignored\n' > "$$project/lean-toolchain"; \
	cd "$$project/sub/child"; export ELAN_HOME="$$home" LEAN_RECURSION_COUNT=0 KEEP=selection PATH=/usr/bin:/bin; \
	check() { \
		expect=$$1; program=$$2; shift 2; status=0; \
		"$$proxy" lean "$$@" 'space arg' '' '+later' > "$$base/got" 2> "$$base/err" || status=$$?; \
		test "$$status" -eq 37 || { cat "$$base/err"; return 1; }; \
		if test -n "$${notice_file:-}"; then cmp "$$notice_file" "$$base/err"; else test ! -s "$$base/err"; fi; \
		printf '%s\n' "$$program/bin/lean" 'space arg' '' '+later' 'KEEP=selection' \
			"ELAN_HOME=$$home" "ELAN_TOOLCHAIN=$$expect" 'LEAN_RECURSION_COUNT=1' \
			"PATH=$$home/bin:/usr/bin:/bin" | cmp - "$$base/got"; \
	}; \
	bad() { \
		status=0; "$$proxy" lean "$$@" > "$$base/got" 2> "$$base/err" || status=$$?; \
		test "$$status" -eq 2 && test ! -s "$$base/got" && test -s "$$base/err"; \
	}; \
	export ELAN_TOOLCHAIN=env; check cli "$$home/toolchains/cli" +cli; check env "$$home/toolchains/env"; \
	export ELAN_TOOLCHAIN=; check project "$$home/toolchains/project"; \
	printf '4.19.0\n' > "$$project/sub/lean-toolchain"; check "$$pinned" "$$installed"; \
	ln -s "$$root" "$$project/relative-root"; printf 'relative-root\n' > "$$project/lean-toolchain"; \
	rm "$$project/sub/lean-toolchain"; check "$$project/relative-root" "$$project/relative-root"; \
	printf '\302\240project\343\200\200\r\n' > "$$project/lean-toolchain"; check project "$$home/toolchains/project"; \
	printf 'project\n' > "$$project/lean-toolchain"; \
	dd if=/dev/zero bs=8191 count=8 2>/dev/null | tr '\000' ' ' >> "$$project/lean-toolchain"; \
	check project "$$home/toolchains/project"; printf ' ' >> "$$project/lean-toolchain"; bad; \
	printf ' \nproject\n' > "$$project/lean-toolchain"; bad; \
	printf 'project\n\377' > "$$project/lean-toolchain"; bad; \
	printf 'project\000bad' > "$$project/lean-toolchain"; bad; \
	rm "$$project/lean-toolchain"; check default "$$home/toolchains/default"; \
	printf 'version = "17"\n' > "$$home/settings.toml"; bad; check cli "$$home/toolchains/cli" +cli; \
	rm "$$home/settings.toml"; bad; bad +stable; bad +; \
	printf 'version = "12"\ndefault_toolchain = "default"\n[overrides]\n' > "$$home/settings.toml"; \
	printf '"%s" = "project"\n' "$$project" >> "$$home/settings.toml"; \
	printf 'cli\n' > "$$project/lean-toolchain"; export ELAN_NO_OVERRIDE_NOTICE=; \
	check project "$$home/toolchains/project"; \
	printf 'cli\n' > "$$project/sub/lean-toolchain"; check cli "$$home/toolchains/cli"; \
	printf '"%s" = "%s"\n' "$$project/sub" "$$pinned" >> "$$home/settings.toml"; \
	check "$$pinned" "$$installed"; export ELAN_TOOLCHAIN=env; check env "$$home/toolchains/env"; \
	check cli "$$home/toolchains/cli" +cli; unset ELAN_TOOLCHAIN ELAN_NO_OVERRIDE_NOTICE; \
	notice_file="$$base/notice"; \
	printf "note: using toolchain '%s' from override set on '%s'\nnote: to remove: elan override unset --path '%s' | to suppress: ELAN_NO_OVERRIDE_NOTICE=1\n" \
		"$$pinned" "$$project/sub" "$$project/sub" > "$$notice_file"; \
	check "$$pinned" "$$installed"; unset notice_file; \
	mkdir "$$installed/deep"; cd "$$installed/deep"; check "$$pinned" "$$installed"; \
	printf 'env\n' > "$$installed/lean-toolchain"; check env "$$home/toolchains/env"; \
	cd "$$base"; check default "$$home/toolchains/default"; \
	mkdir -p "$$base/legacy/nested"; cd "$$base/legacy/nested"; \
	printf '[package]\nname = "project"\nversion = "0.1"\nlean_version = "env"\npath = "src"\n[dependencies]\nmathlib = { git = "url", rev = "rev" }\n' > ../leanpkg.toml; \
	check env "$$home/toolchains/env"; printf 'cli\n' > ../lean-toolchain; check cli "$$home/toolchains/cli"; \
	printf '[package]\nlean_version = "%s"\n' "$$pinned" > leanpkg.toml; check "$$pinned" "$$installed"; \
	printf '[package]\nname = "no-selection"\n' > leanpkg.toml; check cli "$$home/toolchains/cli"; \
	printf '[package]\nlean_version = false\n' > leanpkg.toml; bad; \
	check env "$$home/toolchains/env" +env; \
	ln -s "$$root" ./relative-root; rm leanpkg.toml ../lean-toolchain; \
	printf '[package]\nlean_version = "./relative-root"\n' > ../leanpkg.toml; check ././relative-root ././relative-root; \
	printf '%s\n' 'elan local selection tests passed'
