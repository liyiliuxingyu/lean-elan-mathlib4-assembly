zstd_objects := $(addprefix $(BUILD_DIR)/,zstd.o zstd_xxh64.o zstd_huff.o zstd_fse.o zstd_sequences.o)

$(BUILD_DIR)/zstd.o $(BUILD_DIR)/zstd_test.o: zstd.inc

$(BUILD_DIR)/zstd-test: $(BUILD_DIR)/zstd_test.o $(zstd_objects)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/zstd-huff-test: $(BUILD_DIR)/zstd_huff_test.o $(BUILD_DIR)/zstd_huff.o $(BUILD_DIR)/zstd_fse.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/zstd-history-test: $(BUILD_DIR)/zstd_history_test.o $(BUILD_DIR)/zstd_sequences.o $(BUILD_DIR)/zstd_huff.o $(BUILD_DIR)/zstd_fse.o
	$(LD) $(LDFLAGS) -o "$@" $^

.PHONY: test-zstd
test-zstd: $(BUILD_DIR)/zstd-test $(BUILD_DIR)/zstd-huff-test $(BUILD_DIR)/zstd-history-test
	"$(BUILD_DIR)/zstd-test"
	"$(BUILD_DIR)/zstd-huff-test"
	"$(BUILD_DIR)/zstd-history-test"

$(BUILD_DIR)/zstd_oracle.o: zstd.inc

$(BUILD_DIR)/zstd-oracle: $(BUILD_DIR)/zstd_oracle.o $(zstd_objects)
	$(CC) $(LDFLAGS) -o "$@" $^ -lzstd

# Read each real archive with the directory reader. Check the isolated
# Zstandard frames before LGZ expansion so both sides produce the same layer.
.PHONY: test-zstd-oracle
test-zstd-oracle: $(BUILD_DIR)/zstd-oracle $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/zstd_dict.o
	@set -eu; test -d "$(ZSTD_ARCHIVES)"; \
	scratch=$$(mktemp -d); trap 'rm -rf -- "$$scratch"' EXIT; \
	$(OBJCOPY) -O binary -j .rodata.mathlib_zstd_dict "$(BUILD_DIR)/zstd_dict.o" "$$scratch/dict"; \
	total=0; count=0; \
	for archive in "$(ZSTD_ARCHIVES)"/*.ltar; do \
	  test -f "$$archive"; count=$$((count + 1)); \
	  "$(BUILD_DIR)/mathlib-ltar" --list "$$archive" > "$$scratch/list"; \
	  while read -r kind off len member; do \
	    case "$$kind" in zstd|lgz) ;; *) continue ;; esac; \
	    dd status=none if="$$archive" of="$$scratch/frame" iflag=skip_bytes,count_bytes skip="$$off" count="$$len"; \
	    set -- "$$scratch/frame"; if [ "$$kind" = lgz ]; then set -- "$$@" "$$scratch/dict"; fi; \
	    "$(BUILD_DIR)/zstd-oracle" "$$@" || { echo "failed: $$archive $$member" >&2; exit 1; }; \
	    total=$$((total + 1)); \
	  done < "$$scratch/list"; \
	done; test "$$total" -gt 0; \
	printf 'libzstd matched %s frames across %s archives\n' "$$total" "$$count"
