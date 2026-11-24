archive_reader := $(BUILD_DIR)/ltar_directory.o $(BUILD_DIR)/catalog_archive.o \
   $(BUILD_DIR)/ltar_zstd_stream.o $(BUILD_DIR)/ltar-utf8.o $(cache_reader) \
   $(lgz_objects) $(zstd_objects) $(BUILD_DIR)/zstd_dict.o
catalog_objects := $(addprefix $(BUILD_DIR)/,catalog_cli.o catalog_build.o catalog_index.o \
   catalog_save.o catalog_memory.o catalog_key.o)
all: $(BUILD_DIR)/mathlib-catalog

$(BUILD_DIR)/mathlib-catalog: $(catalog_objects) $(archive_reader) $(cache_term)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/catalog_cli.o $(BUILD_DIR)/catalog_build.o $(BUILD_DIR)/catalog_memory.o \
$(BUILD_DIR)/catalog_index.o $(BUILD_DIR)/catalog_save.o: catalog_layout.inc

$(BUILD_DIR)/catalog_cli.o $(BUILD_DIR)/catalog_key.o $(BUILD_DIR)/catalog_archive.o \
$(BUILD_DIR)/catalog_build.o $(BUILD_DIR)/catalog_key_test.o $(BUILD_DIR)/catalog_archive_test.o: olean_layout.inc

$(BUILD_DIR)/catalog-key-test: $(BUILD_DIR)/catalog_key_test.o $(BUILD_DIR)/catalog_key.o $(cache_reader)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/catalog-archive-test: $(BUILD_DIR)/catalog_archive_test.o $(archive_reader)
	$(LD) $(LDFLAGS) -o "$@" $^

.PHONY: test-catalog
test: test-catalog
test-catalog: $(BUILD_DIR)/mathlib-catalog $(BUILD_DIR)/catalog-key-test $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/ltar_payload_fixture.o
	"$(BUILD_DIR)/catalog-key-test"
	@set -eu; dir=$$(mktemp -d); trap 'rm -rf -- "$$dir"' EXIT; \
	catcli="$(abspath $(BUILD_DIR))/mathlib-catalog"; ltar="$(abspath $(BUILD_DIR))/mathlib-ltar"; \
	$(OBJCOPY) -O binary -j .ltar_payload "$(BUILD_DIR)/ltar_payload_fixture.o" "$$dir/first"; \
	cd "$$dir"; cp first second; \
	"$$catcli" build index first second; \
	"$$catcli" stats index > out; printf 'archives\t2\ndeclarations\t2\nunqueryable\t0\n' | cmp - out; \
	"$$catcli" lookup index '«cacheStageSix»' cacheStageSix > out; \
	printf 'theorem\t%s\t%s/first\n' '«cacheStageSix»' "$$dir" cacheStageSix "$$dir" | cmp - out; \
	"$$ltar" --term first cacheStageSix > proof; "$$catcli" term index cacheStageSix > out; cmp proof out; \
	fail() { expect=$$1; shift; status=0; "$$catcli" "$$@" >out 2>err || status=$$?; test "$$status" -eq "$$expect"; }; \
	fail 1 lookup index absent cacheStageSix absent; \
	printf 'missing\tabsent\ntheorem\tcacheStageSix\t%s/first\nmissing\tabsent\n' "$$dir" | cmp - out; \
	cp index original; fail 2 build index first missing-file; cmp original index; test -s err; \
	"$$catcli" build index second first; "$$catcli" lookup index cacheStageSix > out; \
	printf 'theorem\tcacheStageSix\t%s/second\n' "$$dir" | cmp - out; \
	printf '\000changed-comment\000' >> second; fail 2 term index cacheStageSix; test ! -s out; grep -q 'differs' err; \
	rm second; "$$catcli" lookup index cacheStageSix > out; fail 2 term index cacheStageSix; test ! -s out; \
	printf 'keep' > other; fail 2 build other first; printf 'keep' | cmp - other; \
	ln -s original pointer; fail 2 build pointer first; test -L pointer; \
	cp original truncated; truncate -s -1 truncated; fail 2 lookup truncated x; test ! -s out; \
	cp original damaged; printf '\377\377\377\377\377\377\377\377' | dd of=damaged bs=1 seek=24 conv=notrunc status=none; fail 2 stats damaged; \
	long=$$(awk 'BEGIN { for(i=0; i<19000; ++i) printf "a" }'); \
	fail 1 lookup index "$$long" cacheStageSix "$$long"; \
	printf 'missing\t%s\ntheorem\tcacheStageSix\t%s/second\nmissing\t%s\n' "$$long" "$$dir" "$$long" | cmp - out; \
	fail 2 lookup index 'bad..name'; test ! -s out; \
	status=0; "$$catcli" lookup index cacheStageSix > /dev/full 2>err || status=$$?; test "$$status" -eq 2; \
	printf '%s\n' 'catalog snapshot, precedence, atomic rebuild, stale proof and query tests passed'
