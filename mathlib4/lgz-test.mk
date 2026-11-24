# The binary takes the raw object stream after the outer zstd decoder.
lgz_objects := $(BUILD_DIR)/lgz_decode.o $(BUILD_DIR)/lgz_expr_data.o $(BUILD_DIR)/lgz-hash.o

$(BUILD_DIR)/lgz-hash.o: ../lean4/hash.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o "$@" "$<"

$(BUILD_DIR)/mathlib-lgz: $(BUILD_DIR)/lgz_cli.o $(lgz_objects)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/lgz-test: $(BUILD_DIR)/lgz_test.o $(BUILD_DIR)/lgz_fixture.o $(lgz_objects)
	$(LD) $(LDFLAGS) -o "$@" $^

.PHONY: test-lgz
test-lgz: $(BUILD_DIR)/mathlib-lgz $(BUILD_DIR)/lgz-test $(BUILD_DIR)/lgz_expr_fixture.o
	"$(BUILD_DIR)/lgz-test"
	@set -eu; tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; \
	reader="$(BUILD_DIR)/mathlib-lgz"; \
	for name in v0 v1 normal deep wide; do \
	    $(OBJCOPY) -O binary -j ".lgz_$$name" "$(BUILD_DIR)/lgz_fixture.o" "$$tmp/$$name.lgz"; \
	    (ulimit -s 256; "$$reader" "$$tmp/$$name.lgz") > "$$tmp/$$name.olean"; \
	done; \
	$(OBJCOPY) -O binary -j .lgz_expr_fixture "$(BUILD_DIR)/lgz_expr_fixture.o" "$$tmp/expr.lgz"; \
	"$$reader" "$$tmp/expr.lgz" > "$$tmp/expr.olean"; \
	(cd "$$tmp"; printf '%s\n' \
	    '359908392999096d8e803d682cc8dade597fec2a9cebd016b0f0ac3a83b4763f  v0.olean' \
	    'e0e3c85c13aeafb1922cf1bef9c928b36306d74909b104f14115f571c6ac260e  v1.olean' \
	    '46e456ccf07d4ad89494f4b777e409c6f9e5e23cb5febdc383255d1d58319d06  normal.olean' \
	    '1af238f2fb99dd4f3f1a9d2a2bcb35077ffabb418ea576fbf54c06667d413484  wide.olean' \
	    'c493792af051ff57b7757cf44f7c7287e9abdcb8855a002a64dd7432fc23e813  deep.olean' \
	    '497407888c0299551c900a58bea96a6969e554aeb67f4fa88b8265887c5e439d  expr.olean' \
	    | sha256sum -c -); \
	status=0; "$$reader" "$$tmp/normal.lgz" > /dev/full 2> "$$tmp/stderr" || status=$$?; \
	test "$$status" -eq 2; test -s "$$tmp/stderr"
