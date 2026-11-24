BUILD_DIR ?= build
LEAN ?= lean

objects := $(BUILD_DIR)/verify.o $(BUILD_DIR)/nat_succ_injective.o
cache_reader := $(BUILD_DIR)/olean_read.o
cache_cli := $(BUILD_DIR)/olean_cli.o
cache_test := $(BUILD_DIR)/olean_test.o

.PHONY: all test test-lean test-cache
all: $(BUILD_DIR)/selftest $(BUILD_DIR)/export-lean $(BUILD_DIR)/mathlib-olean

$(BUILD_DIR):
	mkdir -p "$@"

$(objects) $(BUILD_DIR)/selftest.o $(BUILD_DIR)/export_lean.o: proof_format.inc
$(cache_reader) $(cache_cli) $(cache_test): olean_layout.inc

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) --64 -I . $(ASFLAGS) -o "$@" "$<"

$(BUILD_DIR)/selftest: $(objects) $(BUILD_DIR)/selftest.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/export-lean: $(objects) $(BUILD_DIR)/export_lean.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/mathlib-olean: $(cache_cli) $(cache_reader)
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/olean-test: $(cache_test) $(cache_reader)
	$(LD) $(LDFLAGS) -o "$@" $^

test-cache: $(BUILD_DIR)/olean-test
	"$(BUILD_DIR)/olean-test"

test: $(BUILD_DIR)/selftest test-cache
	"$(BUILD_DIR)/selftest"

test-lean: $(BUILD_DIR)/export-lean
	"$(BUILD_DIR)/export-lean" > "$(BUILD_DIR)/NatSuccInjective.lean"
	"$(LEAN)" "$(BUILD_DIR)/NatSuccInjective.lean"
