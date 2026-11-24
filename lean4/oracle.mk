# Included from the root Makefile, which supplies the object build rules.
.PHONY: test-kernel-oracle
test-kernel-oracle: $(runtime)/kernel-data-oracle.o $(runtime)/kernel-data.o
	@set -eu; \
	commit=$$("$(LEAN)" --githash); \
	if [ "$$commit" != 6caaee842e9495688c1567e78c0e68dbb96942aa ]; then \
		echo 'test-kernel-oracle requires the official Lean v4.19.0 Linux x86-64 release' >&2; exit 1; \
	fi; \
	prefix=$$("$(LEAN)" --print-prefix); \
	libdir="$$prefix/lib/lean"; \
	export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
	$(CC) $(LDFLAGS) -o "$(runtime)/kernel-oracle-stock" \
	  "$(runtime)/kernel-data-oracle.o" -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	$(CC) $(LDFLAGS) -o "$(runtime)/kernel-oracle-asm" \
	  "$(runtime)/kernel-data-oracle.o" "$(runtime)/kernel-data.o" \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	"$(runtime)/kernel-oracle-stock" > "$(runtime)/kernel-oracle-stock.txt"; \
	"$(runtime)/kernel-oracle-asm" > "$(runtime)/kernel-oracle-asm.txt"; \
	cmp "$(runtime)/kernel-oracle-stock.txt" "$(runtime)/kernel-oracle-asm.txt"; \
	test "$$(wc -l < "$(runtime)/kernel-oracle-stock.txt")" -eq 15360; \
	echo 'Lean v4.19.0 kernel data: 15,360 comparisons passed'
