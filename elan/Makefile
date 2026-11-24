BUILD_DIR ?= build

.PHONY: all test test-run-proxy clean
all: $(BUILD_DIR)/elan-asm-descriptor $(BUILD_DIR)/elan-asm-run

test: all $(BUILD_DIR)/test-toolchain-desc test-run-proxy
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

$(BUILD_DIR)/test-toolchain-desc: $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/test-run-probe: $(BUILD_DIR)/test_run_probe.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

clean:
	$(RM) $(BUILD_DIR)/elan-asm-run $(BUILD_DIR)/run_proxy.o
	$(RM) $(BUILD_DIR)/test-run-probe $(BUILD_DIR)/test_run_probe.o
	rm -f $(BUILD_DIR)/elan-asm-descriptor $(BUILD_DIR)/test-toolchain-desc
	rm -f $(BUILD_DIR)/descriptor_cli.o $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o
