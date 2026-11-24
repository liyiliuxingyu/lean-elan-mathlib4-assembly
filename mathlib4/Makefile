BUILD_DIR ?= build
LEAN ?= lean
OBJCOPY ?= objcopy

objects := $(BUILD_DIR)/verify.o $(BUILD_DIR)/nat_succ_injective.o
cache_reader := $(BUILD_DIR)/olean_read.o
cache_cli := $(BUILD_DIR)/olean_cli.o
cache_graph := $(BUILD_DIR)/olean_graph.o $(BUILD_DIR)/olean_search_path.o
cache_term := $(BUILD_DIR)/olean_term.o $(BUILD_DIR)/olean_term_data.o
cache_test := $(BUILD_DIR)/olean_test.o

.PHONY: all test test-lean test-cache test-graph test-term
all: $(BUILD_DIR)/selftest $(BUILD_DIR)/export-lean $(BUILD_DIR)/mathlib-olean

$(BUILD_DIR):
	mkdir -p "$@"

$(objects) $(BUILD_DIR)/selftest.o $(BUILD_DIR)/export_lean.o: proof_format.inc
$(cache_reader) $(cache_cli) $(cache_test) $(cache_term) $(BUILD_DIR)/olean_graph.o: olean_layout.inc

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) --64 -I . $(ASFLAGS) -o "$@" "$<"

$(BUILD_DIR)/selftest: $(objects) $(BUILD_DIR)/selftest.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/export-lean: $(objects) $(BUILD_DIR)/export_lean.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/mathlib-olean: $(cache_cli) $(cache_reader) $(cache_graph) $(cache_term)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/olean-test: $(cache_test) $(cache_reader)
	$(LD) $(LDFLAGS) -o "$@" $^

test-cache: $(BUILD_DIR)/olean-test test-graph test-term
	"$(BUILD_DIR)/olean-test"

test-graph: $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/olean_graph_fixture.o
	@set -eu; \
	scratch=$$(mktemp -d); \
	trap 'rm -rf -- "$$scratch"' EXIT; \
	full="$$scratch/full"; shadow="$$scratch/shadow"; \
	mkdir -p "$$full/CacheTest" "$$shadow/CacheTest"; \
	fixture="$(BUILD_DIR)/olean_graph_fixture.o"; \
	$(OBJCOPY) -O binary -j .graph_root "$$fixture" "$$full/CacheTest/Root.olean"; \
	$(OBJCOPY) -O binary -j .graph_left "$$fixture" "$$full/CacheTest/Left.olean"; \
	$(OBJCOPY) -O binary -j .graph_right "$$fixture" "$$full/CacheTest/Right.olean"; \
	$(OBJCOPY) -O binary -j .graph_leaf "$$fixture" "$$full/CacheTest/Leaf.olean"; \
	reader="$(BUILD_DIR)/mathlib-olean"; root="$$full/CacheTest/Root.olean"; \
	LEAN_PATH="$$full" "$$reader" --recursive "$$root" \
		cacheTestRoot cacheTestLeft cacheTestRight cacheTestLeaf > "$$scratch/result"; \
	printf 'axiom\t%s\n' cacheTestRoot cacheTestLeft cacheTestRight cacheTestLeaf | cmp - "$$scratch/result"; \
	if LEAN_PATH="$$full" "$$reader" --recursive "$$root" \
		cacheTestLeaf cacheTestMissing > "$$scratch/result"; then exit 1; else test "$$?" -eq 1; fi; \
	printf 'axiom\tcacheTestLeaf\nmissing\tcacheTestMissing\n' | cmp - "$$scratch/result"; \
	if LEAN_PATH="$$shadow:$$full" "$$reader" --recursive "$$root" \
		cacheTestLeaf > "$$scratch/result" 2> "$$scratch/error"; then exit 1; else test "$$?" -eq 2; fi; \
	grep -Fq "$$shadow/CacheTest/Left.olean" "$$scratch/error"; \
	LEAN_PATH="$$shadow" "$$reader" --recursive "$$root" cacheTestRoot > "$$scratch/result"; \
	printf 'axiom\tcacheTestRoot\n' | cmp - "$$scratch/result"; \
	printf '%s\n' 'olean graph tests passed'

$(BUILD_DIR)/olean-term-data-test: $(BUILD_DIR)/olean_term_data_test.o $(BUILD_DIR)/olean_term_data.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/olean_term_data_test.o: olean_layout.inc

test-term: $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/olean_graph_fixture.o $(BUILD_DIR)/olean-term-data-test
	"$(BUILD_DIR)/olean-term-data-test"
	@set -eu; \
	scratch=$$(mktemp -d); \
	trap 'rm -rf -- "$$scratch"' EXIT; \
	$(OBJCOPY) -O binary -j .graph_term "$(BUILD_DIR)/olean_graph_fixture.o" "$$scratch/Term.olean"; \
	"$(BUILD_DIR)/mathlib-olean" --term "$$scratch/Term.olean" cacheTestTerm > "$$scratch/output"; \
	awk -F '\t' 'NR == 1 { if ($$1 != "type" || $$2 <= 0) exit 1; t = $$2 } \
		NR == 2 { if ($$1 != "proof" || $$2 <= 0) exit 1; p = $$2 } \
		NR == 3 { if ($$1 != "expr" || $$2 != t || $$3 != "const" || $$4 != "True" || $$5 != 0) exit 1 } \
		NR == 4 { if ($$1 != "expr" || $$2 != p || $$3 != "const" || $$4 != "True.intro" || $$5 != 0) exit 1 } \
		END { if (NR != 4) exit 1 }' "$$scratch/output"; \
	$(OBJCOPY) -O binary -j .graph_term_cycle "$(BUILD_DIR)/olean_graph_fixture.o" "$$scratch/Cycle.olean"; \
	if "$(BUILD_DIR)/mathlib-olean" --term "$$scratch/Cycle.olean" cacheTestTermCycle \
		> "$$scratch/output" 2> "$$scratch/error"; then exit 1; else test "$$?" -eq 2; fi; \
	printf '%s\n' 'olean term tests passed'

test: $(BUILD_DIR)/selftest test-cache
	"$(BUILD_DIR)/selftest"

test-lean: $(BUILD_DIR)/export-lean
	"$(BUILD_DIR)/export-lean" > "$(BUILD_DIR)/NatSuccInjective.lean"
	"$(LEAN)" "$(BUILD_DIR)/NatSuccInjective.lean"
