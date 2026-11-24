# GNU Make fragment for the pinned Lean Linux x86-64 differential tests.
OBJCOPY ?= objcopy
LEANTAR ?= leantar

.PHONY: test-expr-shift-oracle test-expr-shift-corpus
test-upstream: test-expr-shift-oracle

define shift_lean_environment
test "$$("$(LEAN)" --githash)" = 6caaee842e9495688c1567e78c0e68dbb96942aa || \
  { echo 'Lean v4.19.0 Linux x86-64 required' >&2; exit 1; }; \
prefix=$$("$(LEAN)" --print-prefix); libdir="$$prefix/lib/lean"; \
export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"
endef

test-expr-shift-oracle: $(runtime)/expr-shift-oracle.o $(runtime)/expr-shift.o
	@set -eu; $(shift_lean_environment); \
	$(CC) $(LDFLAGS) -o "$(runtime)/expr-shift-stock" "$<" \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	$(CC) $(LDFLAGS) -o "$(runtime)/expr-shift-asm" $^ \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	"$(runtime)/expr-shift-stock" > "$(runtime)/expr-shift-stock.txt"; \
	"$(runtime)/expr-shift-asm" > "$(runtime)/expr-shift-asm.txt"; \
	cmp "$(runtime)/expr-shift-stock.txt" "$(runtime)/expr-shift-asm.txt"; \
	test "$$(wc -l < "$(runtime)/expr-shift-stock.txt")" -eq 4320; \
	echo 'Lean v4.19.0 binder-aware index shifts: 4,320 comparisons passed'

# A private copy with distinct symbols lets the module driver call both versions
# on the very same compacted input objects in one process.
$(runtime)/expr-shift-renamed.o: $(runtime)/expr-shift.o
	$(OBJCOPY) --redefine-sym lean_expr_lift_loose_bvars=asm_expr_lift_loose_bvars \
	  --redefine-sym lean_expr_lower_loose_bvars=asm_expr_lower_loose_bvars \
	  --redefine-sym l_Lean_Expr_liftLooseBVars___boxed=asm_expr_lift_boxed \
	  --redefine-sym l_Lean_Expr_lowerLooseBVars___boxed=asm_expr_lower_boxed "$<" "$@"

test-expr-shift-corpus: $(runtime)/expr-shift-module.o $(runtime)/expr-shift-renamed.o
	@set -eu; $(shift_lean_environment); \
	test -n "$(LTAR_CORPUS)" || { echo 'set LTAR_CORPUS to the pinned archive directory' >&2; exit 1; }; \
	test "$$("$(LEANTAR)" --version)" = 'leantar 0.1.15'; \
	corpus="$(abspath $(LTAR_CORPUS))"; manifest="$(abspath mathlib4/ltar-corpus.sha256)"; \
	(cd "$$corpus" && sha256sum --check --strict "$$manifest"); \
	tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; mkdir "$$tmp/modules"; \
	while read -r digest file; do \
	  "$(LEANTAR)" --jobs 1 -f -C "$$tmp/modules" -x "$$corpus/$$file"; \
	done < "$$manifest"; \
	$(CC) $(LDFLAGS) -o "$(runtime)/expr-shift-module" $^ \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	find "$$tmp/modules" -type f -name '*.olean' | LC_ALL=C sort > "$$tmp/list"; \
	while IFS= read -r module; do \
	  "$(runtime)/expr-shift-module" "$$module" >> "$$tmp/rows"; \
	done < "$$tmp/list"; \
	awk '{ t+=$$1; n+=$$2; c+=$$3; h+=$$4 } \
	   END { if (NR!=13 || t!=61 || n!=3197 || c!=38364 || h!=26805) exit 1 }' "$$tmp/rows"; \
	echo '13 modules, 61 theorems, 3,197 nodes: 38,364 shift comparisons passed (26,805 changed roots)'
