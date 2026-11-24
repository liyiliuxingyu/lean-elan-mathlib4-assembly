.PHONY: test-ltar-payload
test-ltar: test-ltar-payload
test-ltar-payload: $(BUILD_DIR)/catalog-archive-test $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/ltar_payload_fixture.o $(BUILD_DIR)/ltar_fixture.o
	@set -eu; tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; \
	reader="$(BUILD_DIR)/mathlib-ltar"; fixture="$(BUILD_DIR)/ltar_payload_fixture.o"; \
	$(OBJCOPY) -O binary -j .ltar_payload "$$fixture" "$$tmp/module"; \
	$(OBJCOPY) -O binary -j .ltar_duplicate "$$fixture" "$$tmp/extra"; \
	$(OBJCOPY) -O binary -j .ltar_v1 "$(BUILD_DIR)/ltar_fixture.o" "$$tmp/legacy"; \
	"$$reader" --cat "$$tmp/legacy" t > "$$tmp/out"; printf '17' | cmp - "$$tmp/out"; \
	"$$reader" --cat "$$tmp/legacy" a > "$$tmp/out"; printf '18446744073709551615' | cmp - "$$tmp/out"; \
	"$$reader" --cat "$$tmp/module" tiny.trace > "$$tmp/out"; \
	printf '%s' '{"log":[],"depHash":"18446744073709551615"}' | cmp - "$$tmp/out"; \
	"$$reader" --cat "$$tmp/module" tiny.bin > "$$tmp/out"; printf '\000\012\377\134\000' | cmp - "$$tmp/out"; \
	"$$reader" --cat "$$tmp/module" concatenated.bin > "$$tmp/out"; printf 'onetwo' | cmp - "$$tmp/out"; \
	for member in empty-frames.bin skip-only.bin; do \
	    "$$reader" --cat "$$tmp/module" "$$member" > "$$tmp/out"; test ! -s "$$tmp/out"; \
	done; \
	"$$reader" --cat "$$tmp/module" lib/Tiny.olean > "$$tmp/Tiny.olean"; \
	(cd "$$tmp"; printf '%s\n' 'c0c49f7bc79f357261bf26c501cd2bc13e7df353749ad4d48300c427f3c9fcd3  Tiny.olean' | sha256sum -c -); \
	status=0; "$$reader" --lookup "$$tmp/module" cacheStageSix absent cacheStageSix > "$$tmp/out" || status=$$?; \
	test "$$status" -eq 1; printf 'theorem\tcacheStageSix\nmissing\tabsent\ntheorem\tcacheStageSix\n' | cmp - "$$tmp/out"; \
	"$$reader" --term "$$tmp/module" cacheStageSix > "$$tmp/out"; \
	"$(BUILD_DIR)/mathlib-olean" --term "$$tmp/Tiny.olean" cacheStageSix | cmp - "$$tmp/out"; \
	expect_failure() { expected=$$1; shift; status=0; "$$reader" "$$@" > "$$tmp/out" 2> "$$tmp/err" || status=$$?; \
	    test "$$status" -eq "$$expected"; test ! -s "$$tmp/out"; test -s "$$tmp/err"; }; \
	expect_failure 1 --cat "$$tmp/module" absent; expect_failure 2 --term "$$tmp/legacy" absent; \
	$(OBJCOPY) -O binary -j .ltar_stream_faults "$$fixture" "$$tmp/faults"; \
	cat "$$tmp/module" "$$tmp/faults" > "$$tmp/bad-streams"; \
	for member in no-frames.bin short-skip-header.bin short-skip-body.bin short-frame.bin bad-checksum.bin; do \
	    expect_failure 2 --cat "$$tmp/bad-streams" "$$member"; \
	done; \
	cat "$$tmp/module" "$$tmp/extra" > "$$tmp/ambiguous"; \
	expect_failure 2 --cat "$$tmp/ambiguous" lib/Tiny.olean; expect_failure 2 --lookup "$$tmp/ambiguous" cacheStageSix; \
	cp "$$tmp/module" "$$tmp/trailing"; printf 'unterminated' >> "$$tmp/trailing"; \
	expect_failure 2 --cat "$$tmp/trailing" tiny.trace; expect_failure 2 --term "$$tmp/trailing" cacheStageSix; \
	$(OBJCOPY) -O binary -j .ltar_v2 "$(BUILD_DIR)/ltar_fixture.o" "$$tmp/bad_zstd"; \
	expect_failure 2 --cat "$$tmp/bad_zstd" x.olean; \
	status=0; "$$reader" --cat "$$tmp/module" tiny.bin > /dev/full 2> "$$tmp/err" || status=$$?; \
	test "$$status" -eq 2; test -s "$$tmp/err"; \
	for kind in empty_lgz bad_image; do \
	    $(OBJCOPY) -O binary -j .catalog_$$kind "$(BUILD_DIR)/catalog_archive_test.o" "$$tmp/$$kind"; \
	done; \
	"$(BUILD_DIR)/catalog-archive-test" "$$tmp/module" "$$tmp/legacy" "$$tmp/bad_zstd" "$$tmp/empty_lgz" \
	    "$$tmp/bad_image" "$$tmp/ambiguous" "$$tmp/trailing" "$$tmp/absent" "$$tmp"; \
	printf '%s\n' 'ltar payload and theorem tests passed'

# Optional external oracle. Supply a directory of official cache downloads and
# leantar 0.1.15. Each archive is unpacked into its own fresh reference folder.
LEANTAR ?= leantar
.PHONY: test-ltar-oracle
test-ltar-oracle: $(BUILD_DIR)/mathlib-ltar
	@set -eu; test -d "$(LTAR_ARCHIVES)"; tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; \
	count=0; total=0; reader="$(BUILD_DIR)/mathlib-ltar"; \
	for archive in "$(LTAR_ARCHIVES)"/*.ltar; do \
	    test -f "$$archive"; count=$$((count + 1)); dir="$$tmp/$$count"; mkdir "$$dir"; \
	    "$(LEANTAR)" -f --jobs 1 -C "$$dir" -d "$$archive"; \
	    "$(LEANTAR)" -k "$$archive" > "$$tmp/expected"; \
	    "$$reader" -k "$$archive" > "$$tmp/actual"; cmp "$$tmp/expected" "$$tmp/actual"; \
	    "$$reader" --list "$$archive" > "$$tmp/list"; n=0; \
	    while IFS="$$(printf '\t')" read -r kind off len escaped; do \
	        member=$$(/usr/bin/printf '%b.' "$$escaped"); member=$${member%.}; \
	        "$$reader" --cat "$$archive" "$$member" > "$$tmp/actual"; cmp "$$dir/$$member" "$$tmp/actual"; \
	        n=$$((n+1)); \
	    done < "$$tmp/list"; \
	    test "$$n" -gt 0; test "$$n" -eq "$$(find "$$dir" -type f -printf x | wc -c)"; total=$$((total+n)); \
	done; printf 'leantar matched %s members across %s archives\n' "$$total" "$$count"
