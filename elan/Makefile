BUILD_DIR ?= build

.PHONY: all test clean
all: $(BUILD_DIR)/elan-asm-descriptor

test: all $(BUILD_DIR)/test-toolchain-desc
	$(BUILD_DIR)/test-toolchain-desc

$(BUILD_DIR)/elan-asm-descriptor: $(BUILD_DIR)/descriptor_cli.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/test-toolchain-desc: $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o $@ $^

$(BUILD_DIR)/%.o: %.s | $(BUILD_DIR)
	$(AS) --64 $(ASFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -f $(BUILD_DIR)/elan-asm-descriptor $(BUILD_DIR)/test-toolchain-desc
	rm -f $(BUILD_DIR)/descriptor_cli.o $(BUILD_DIR)/test_toolchain_desc.o $(BUILD_DIR)/toolchain_desc.o
