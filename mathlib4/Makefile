BUILD_DIR ?= build
LEAN ?= lean
OBJCOPY ?= objcopy

objects := $(BUILD_DIR)/verify.o $(BUILD_DIR)/nat_succ_injective.o
cache_reader := $(BUILD_DIR)/olean_read.o $(BUILD_DIR)/olean_index.o
cache_cli := $(BUILD_DIR)/olean_cli.o
cache_graph := $(BUILD_DIR)/olean_graph.o $(BUILD_DIR)/olean_search_path.o
cache_term := $(BUILD_DIR)/olean_term.o $(BUILD_DIR)/olean_term_data.o
cache_test := $(BUILD_DIR)/olean_test.o

.PHONY: all test test-lean test-cache test-graph test-term
all: $(BUILD_DIR)/selftest $(BUILD_DIR)/export-lean $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/mathlib-lgz

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

test-cache: $(BUILD_DIR)/olean-test test-graph test-term test-batch test-ltar
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

$(BUILD_DIR)/olean_term.o: olean_term_syntax.inc

$(BUILD_DIR)/olean_term_data_test.o: olean_layout.inc

test-term: test-metadata $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/olean_graph_fixture.o $(BUILD_DIR)/olean-term-data-test
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

.PHONY: test-metadata
test-metadata: $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/olean_metadata_fixture.o
	@set -eu; \
	scratch=$$(mktemp -d); trap 'rm -rf -- "$$scratch"' EXIT; \
	fixture="$(BUILD_DIR)/olean_metadata_fixture.o"; \
	$(OBJCOPY) -O binary -j .meta_fixture "$$fixture" "$$scratch/Meta.olean"; \
	$(OBJCOPY) -O binary -j .meta_expected "$$fixture" "$$scratch/expected"; \
	"$(BUILD_DIR)/mathlib-olean" --term "$$scratch/Meta.olean" cacheMetaFixture > "$$scratch/rows"; \
	awk -F '\t' 'BEGIN{OFS="\t"} $$1=="metadata"{print $$4,$$5,($$5=="syntax" && $$6!=0 ? "@" : $$6)}' \
	    "$$scratch/rows" | cmp - "$$scratch/expected"; \
	for fault in 1 2 3; do \
	    $(AS) --64 $(ASFLAGS) --defsym META_FAULT=$$fault -o "$$scratch/fault.o" olean_metadata_fixture.s; \
	    $(OBJCOPY) -O binary -j .meta_fixture "$$scratch/fault.o" "$$scratch/Fault.olean"; \
	    status=0; "$(BUILD_DIR)/mathlib-olean" --term "$$scratch/Fault.olean" cacheMetaFixture \
	        > "$$scratch/result" 2> "$$scratch/error" || status=$$?; \
	    test "$$status" -eq 2; test -s "$$scratch/error"; \
	done; printf '%s\n' 'olean metadata tests passed'

.PHONY: test-batch
test-batch: $(BUILD_DIR)/mathlib-olean
	@set -eu; \
	scratch=$$(mktemp -d); trap 'rm -rf -- "$$scratch"' EXIT; \
	$(AS) --64 -I . $(ASFLAGS) --defsym BULK_FIXTURE=1 -o "$$scratch/bulk.o" olean_test.s; \
	$(OBJCOPY) -O binary -j .data "$$scratch/bulk.o" "$$scratch/bulk.olean"; \
	reader="$(BUILD_DIR)/mathlib-olean"; set --; \
	i=0; while test "$$i" -lt 8; do \
	    set -- "$$@" Nat.succ_injective 'Nat.«has.dot»' Nat.worker.17 absent; \
	    printf 'theorem\tNat.succ_injective\ndefinition\tNat.«has.dot»\ndefinition\tNat.worker.17\nmissing\tabsent\n'; \
	    i=$$((i+1)); done > "$$scratch/expected"; \
	for mode in local recursive; do \
	    status=0; if test "$$mode" = local; then \
	        "$$reader" "$$scratch/bulk.olean" "$$@" > "$$scratch/out" || status=$$?; \
	    else LEAN_PATH="" "$$reader" --recursive "$$scratch/bulk.olean" "$$@" > "$$scratch/out" || status=$$?; fi; \
	    test "$$status" -eq 1; cmp "$$scratch/expected" "$$scratch/out"; \
	done; \
	long=$$(awk 'BEGIN{for(i=0;i<18000;i++)printf "a"}'); \
	status=0; "$$reader" "$$scratch/bulk.olean" "$$@" "$$long" Nat.worker.17 > "$$scratch/out" || status=$$?; \
	test "$$status" -eq 1; printf 'missing\t%s\ndefinition\tNat.worker.17\n' "$$long" >> "$$scratch/expected"; \
	cmp "$$scratch/expected" "$$scratch/out"; \
	status=0; "$$reader" "$$scratch/bulk.olean" "$$@" > /dev/full 2> "$$scratch/error" || status=$$?; \
	test "$$status" -eq 2; grep -Fq 'failed to write' "$$scratch/error"; \
	printf '%s\n' 'olean indexed batch tests passed'

$(BUILD_DIR)/ltar-utf8.o: ../lean4/utf8.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o "$@" "$<"

include lgz-test.mk
include zstd-test.mk

test: test-lgz test-zstd

$(BUILD_DIR)/ltar.o: ltar_payload.inc olean_layout.inc
$(BUILD_DIR)/ltar_zstd_stream.o: zstd.inc

$(BUILD_DIR)/mathlib-ltar: $(BUILD_DIR)/ltar.o $(BUILD_DIR)/ltar_zstd_stream.o $(BUILD_DIR)/ltar-utf8.o $(cache_reader) $(cache_term) $(lgz_objects) $(zstd_objects) $(BUILD_DIR)/zstd_dict.o
	$(LD) $(LDFLAGS) -o "$@" $^

.PHONY: test-ltar
test-ltar: $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/ltar_fixture.o
	@set -eu; \
	scratch=$$(mktemp -d); trap 'rm -rf -- "$$scratch"' EXIT; \
	for section in v1 v2 list_v1 list_v2 comments_v1 comments_v2 bad_size bad_text no_nul bad_tag; do \
	    $(OBJCOPY) -O binary -j .ltar_$$section "$(BUILD_DIR)/ltar_fixture.o" "$$scratch/$$section"; \
	done; reader="$(BUILD_DIR)/mathlib-ltar"; \
	for ver in v1 v2; do \
	    "$$reader" --list "$$scratch/$$ver" > "$$scratch/out"; cmp "$$scratch/list_$$ver" "$$scratch/out"; \
	    "$$reader" -k "$$scratch/$$ver" > "$$scratch/out"; cmp "$$scratch/comments_$$ver" "$$scratch/out"; \
	done; \
	for fault in bad_size bad_text no_nul bad_tag; do for flag in --list -k; do \
	    status=0; "$$reader" "$$flag" "$$scratch/$$fault" > "$$scratch/out" 2> "$$scratch/error" || status=$$?; \
	    test "$$status" -eq 2; test ! -s "$$scratch/out"; test -s "$$scratch/error"; \
	done; done; printf '%s\n' 'ltar metadata tests passed'

include metadata-test.mk

include ltar-payload-test.mk

include ltar-corpus-test.mk
