# Included by the root Makefile after its generic assembly rules.
.PHONY: test-expr-app test-expr-app-oracle

test: test-expr-app
test-upstream: test-expr-app-oracle

$(runtime)/expr-app-test: $(runtime)/expr-app-test.o $(runtime)/expr-app.o
	$(LD) -m elf_x86_64 $(LDFLAGS) -o "$@" $^

test-expr-app: $(runtime)/expr-app-test
	"$<"

test-expr-app-oracle: $(runtime)/expr-app-oracle.o $(runtime)/expr-app.o
	@set -eu; \
	commit=$$("$(LEAN)" --githash); \
	test "$$commit" = 6caaee842e9495688c1567e78c0e68dbb96942aa || \
	  { echo 'test-expr-app-oracle requires the Lean v4.19.0 Linux x86-64 release' >&2; exit 1; }; \
	prefix=$$("$(LEAN)" --print-prefix); \
	libdir="$$prefix/lib/lean"; \
	export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
	$(CC) $(LDFLAGS) -o "$(runtime)/expr-app-stock" \
	  "$(runtime)/expr-app-oracle.o" -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	$(CC) $(LDFLAGS) -o "$(runtime)/expr-app-asm" \
	  "$(runtime)/expr-app-oracle.o" "$(runtime)/expr-app.o" \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	"$(runtime)/expr-app-stock" > "$(runtime)/expr-app-stock.txt"; \
	"$(runtime)/expr-app-asm" > "$(runtime)/expr-app-asm.txt"; \
	cmp "$(runtime)/expr-app-stock.txt" "$(runtime)/expr-app-asm.txt"; \
	test "$$(wc -l < "$(runtime)/expr-app-stock.txt")" -eq 1261; \
	echo 'Lean v4.19.0 expression application spines: 1,261 comparisons passed'
