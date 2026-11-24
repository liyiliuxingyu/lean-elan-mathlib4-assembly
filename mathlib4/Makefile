BUILD_DIR ?= build
LEAN ?= lean

objects := $(BUILD_DIR)/verify.o $(BUILD_DIR)/nat_succ_injective.o

.PHONY: all test test-lean
all: $(BUILD_DIR)/selftest $(BUILD_DIR)/export-lean

$(BUILD_DIR):
	mkdir -p "$@"

$(BUILD_DIR)/%.o: %.s proof_format.inc | $(BUILD_DIR)
	$(AS) --64 -I . $(ASFLAGS) -o "$@" "$<"

$(BUILD_DIR)/selftest: $(objects) $(BUILD_DIR)/selftest.o
	$(LD) $(LDFLAGS) -o "$@" $^

$(BUILD_DIR)/export-lean: $(objects) $(BUILD_DIR)/export_lean.o
	$(LD) $(LDFLAGS) -o "$@" $^

test: $(BUILD_DIR)/selftest
	"$(BUILD_DIR)/selftest"

test-lean: $(BUILD_DIR)/export-lean
	"$(BUILD_DIR)/export-lean" > "$(BUILD_DIR)/NatSuccInjective.lean"
	"$(LEAN)" "$(BUILD_DIR)/NatSuccInjective.lean"
