.PHONY: test-pairing
all: $(BUILD_DIR)/mathlib-pairing
test: test-pairing

$(BUILD_DIR)/mathlib-pairing: $(BUILD_DIR)/pairing_cli.o $(BUILD_DIR)/pairing_nat.o
	$(LD) $(LDFLAGS) -o "$@" $^

test-pairing: $(BUILD_DIR)/mathlib-pairing $(BUILD_DIR)/pairing_fixtures.o
	@set -eu; work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
	reader="$(BUILD_DIR)/mathlib-pairing"; \
	$(OBJCOPY) -O binary -j .pairing_cases "$(BUILD_DIR)/pairing_fixtures.o" "$$work/cases"; \
	while read -r a b n; do \
	    test "$$("$$reader" pair "$$a" "$$b")" = "$$n"; \
	    test "$$("$$reader" unpair "$$n")" = "$$a $$b"; \
	done < "$$work/cases"; \
	test "$$("$$reader" pair 00000000001 00000000000000002)" = 5; \
	test "$$("$$reader" unpair 0000000000000000)" = "0 0"; \
	reject() { code=0; "$$reader" "$$@" >"$$work/out" 2>"$$work/err" || code=$$?; \
	    test "$$code" -eq 2 && test ! -s "$$work/out" && test -s "$$work/err"; }; \
	reject; reject unpair; reject pairs 1 2; reject pair 1; reject pair 1 2 3; \
	reject pair '' 0; reject pair 0 +1; reject unpair -1; reject unpair ' 0'; reject unpair 0x1; \
	printf '%s\n' 'Nat.pair and Nat.unpair assembly tests passed'

.PHONY: test-pairing-lean test-pairing-mathlib
test-lean: test-pairing-lean

$(BUILD_DIR)/pairing-queries.txt: $(BUILD_DIR)/pairing_fixtures.o pairing.mk
	@set -eu; work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
	$(OBJCOPY) -O binary -j .pairing_cases "$<" "$$work/triples"; \
	awk '{print "pair", $$1, $$2; print "unpair", $$3}' "$$work/triples" > "$$work/cases"; \
	awk 'BEGIN { for (n=0; n<=255; ++n) print "unpair", n; \
	    for (a=0; a<16; ++a) for (b=0; b<16; ++b) print "pair", a, b; \
	    for (n=1; n<=120; ++n) { s="7"; t="3"; for (k=1; k<=n; ++k) { \
	        s=s ((17*n+19*k+k*k)%10); t=t ((11*n+23*k+n*k)%10) }; \
	        print "unpair", s; print "pair", s, t; print "pair", t, s } }' >> "$$work/cases"; \
	cp "$$work/cases" "$@"

$(BUILD_DIR)/pairing-answers.txt: $(BUILD_DIR)/pairing-queries.txt $(BUILD_DIR)/mathlib-pairing
	@set -eu; work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
	reader="$(BUILD_DIR)/mathlib-pairing"; \
	while read -r op a b; do case "$$op" in \
	    pair) "$$reader" pair "$$a" "$$b" ;; unpair) "$$reader" unpair "$$a" ;; \
	esac; done < "$<" > "$$work/assembly"; \
	cp "$$work/assembly" "$@"

# The first target works with stock Lean/Init. The second uses installed
# Mathlib modules on Lean's search path. Both run exactly the same inputs.
test-pairing-lean test-pairing-mathlib: $(BUILD_DIR)/pairing-answers.txt
	@set -eu; work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
	"$(LEAN)" --version | grep -Fq 'version 4.19.0,'; \
	fixture="$(BUILD_DIR)/pairing_fixtures.o"; \
	if test "$@" = test-pairing-mathlib; then \
	    printf '%s\n' 'import Mathlib.Data.Nat.Pairing' > "$$work/defs"; \
	else $(OBJCOPY) -O binary -j .pairing_defs "$$fixture" "$$work/defs"; fi; \
	$(OBJCOPY) -O binary -j .pairing_main "$$fixture" "$$work/main"; \
	cat "$$work/defs" "$$work/main" > "$$work/Oracle.lean"; \
	"$(LEAN)" --run "$$work/Oracle.lean" "$(BUILD_DIR)/pairing-queries.txt" > "$$work/lean"; \
	cmp "$$work/lean" "$<"; \
	printf '%s Lean 4.19.0 pairing comparisons passed\n' "$$(wc -l < "$<")"

.PHONY: test-pairing-published
PAIRING_ARCHIVES ?= $(LTAR_ARCHIVES)
test-pairing-published: $(BUILD_DIR)/pairing-answers.txt $(BUILD_DIR)/pairing_published_test.o $(BUILD_DIR)/mathlib-ltar
	@set -eu; work=$$(mktemp -d); trap 'rm -rf -- "$$work"' EXIT; \
	test "$$("$(LEAN)" --githash)" = 6caaee842e9495688c1567e78c0e68dbb96942aa; \
	prefix=$$("$(LEAN)" --print-prefix); archives="$(PAIRING_ARCHIVES)"; \
	test -d "$$archives" || { echo 'set PAIRING_ARCHIVES to the directory containing the two caches' >&2; exit 1; }; \
	(cd "$$archives" && printf '%s\n' \
	    'd6a286c527a76aadc3c4f056dbf5944629eadcbd8901854375d9c91f06be9f71  836f4072582cbc3e.ltar' \
	    '914558e2fcfd471bce75e314207297844d8ef0ec41fdc46d8b5eb299f83c5038  7e7ccbecb541d1d5.ltar' | sha256sum -c -); \
	"$(BUILD_DIR)/mathlib-ltar" --cat "$$archives/836f4072582cbc3e.ltar" \
	    '././././.lake/build/ir/Mathlib/Data/Nat/Pairing.c' > "$$work/Pairing.c"; \
	"$(BUILD_DIR)/mathlib-ltar" --cat "$$archives/7e7ccbecb541d1d5.ltar" \
	    '././.lake/packages/batteries/././.lake/build/ir/Batteries/Data/Nat/Basic.c' > "$$work/Basic.c"; \
	(cd "$$work" && printf '%s\n' \
	    'b8e7af4d659eec09e86d9ce95710f0f96c58da7a518b7b35d69cc5f842bd458f  Pairing.c' \
	    'bbf951ac2c412dbd13bf4d1dd1bc8e13255581c46601bf1c480658785243af8c  Basic.c' | sha256sum -c -); \
	$(CC) -O2 -ffunction-sections -fdata-sections -I"$$prefix/include" \
	    "$(BUILD_DIR)/pairing_published_test.o" "$$work/Pairing.c" "$$work/Basic.c" \
	    -L"$$prefix/lib/lean" -Wl,-rpath,"$$prefix/lib/lean" -Wl,--gc-sections -lleanshared -o "$$work/published"; \
	paste "$(BUILD_DIR)/pairing-queries.txt" "$<" | \
	    awk 'NF != 4 || $$2 !~ /^[0-9]+$$/ || $$3 !~ /^[0-9]+$$/ || $$4 !~ /^[0-9]+$$/ { exit 1 } \
	        $$1 == "pair" { print $$2, $$3, $$4; next } $$1 == "unpair" { print $$3, $$4, $$2; next } \
	        { exit 1 } END { if (NR != 924) exit 1 }' > "$$work/triples"; \
	"$$work/published" < "$$work/triples"
