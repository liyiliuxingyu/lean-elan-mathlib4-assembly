BUILD_DIR ?= build
LEAN ?= lean
output := $(abspath $(BUILD_DIR))
runtime := $(output)/lean4
elan_out := $(output)/elan
mathlib_out := $(output)/mathlib4
runtime_objects := $(runtime)/hash.o $(runtime)/utf8.o \
	$(runtime)/utf8-extra.o $(runtime)/utf8-libcxx.o $(runtime)/kernel-data.o
runtime_tests := $(runtime)/hash-test $(runtime)/utf8-test $(runtime)/utf8-extra-test $(runtime)/kernel-data-test

.DELETE_ON_ERROR:
.PHONY: all elan mathlib4 test test-lean
all: $(runtime)/liblean-asm-runtime.a elan mathlib4

$(runtime):
	mkdir -p "$@"

$(runtime)/%.o: lean4/%.s | $(runtime)
	$(AS) --64 $(ASFLAGS) -o "$@" "$<"

$(runtime)/liblean-asm-runtime.a: $(runtime_objects)
	$(AR) rcs "$@" $^

$(runtime)/hash-test: $(runtime)/hash-test.o $(runtime)/hash.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o "$@" $^

$(runtime)/utf8-test: $(runtime)/utf8-test.o $(runtime)/utf8.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o "$@" $^

$(runtime)/utf8-extra-test: $(runtime)/utf8-extra-test.o $(runtime)/utf8-extra.o $(runtime)/utf8.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o "$@" $^

$(runtime)/kernel-data-test: $(runtime)/kernel-data-test.o $(runtime)/kernel-data.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o "$@" $^

elan:
	$(MAKE) -C elan BUILD_DIR="$(elan_out)" all

mathlib4:
	$(MAKE) -C mathlib4 BUILD_DIR="$(mathlib_out)" all

test: all $(runtime_tests)
	"$(runtime)/hash-test"
	"$(runtime)/utf8-test"
	"$(runtime)/utf8-extra-test"
	"$(runtime)/kernel-data-test"
	$(MAKE) -C elan BUILD_DIR="$(elan_out)" test
	$(MAKE) -C mathlib4 BUILD_DIR="$(mathlib_out)" test

test-lean: mathlib4
	$(MAKE) -C mathlib4 BUILD_DIR="$(mathlib_out)" LEAN="$(LEAN)" test-lean

include lean4/oracle.mk

.PHONY: test-upstream
test-upstream: test-lean test-kernel-oracle
