# Optional real-cache differential for the persistent declaration catalog.
.PHONY: test-catalog-corpus
test-catalog-corpus: $(BUILD_DIR)/mathlib-catalog $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/ltar_corpus_names.o
	@set -eu; export LC_ALL=C; \
	test -n "$(LTAR_CORPUS)" || { echo 'set LTAR_CORPUS to the archive directory' >&2; exit 1; }; \
	test "$$("$(LEANTAR)" --version)" = 'leantar 0.1.15'; \
	test "$$("$(LEAN)" --githash)" = '6caaee842e9495688c1567e78c0e68dbb96942aa'; \
	manifest="$(abspath ltar-corpus.sha256)"; corpus="$(abspath $(LTAR_CORPUS))"; \
	(cd "$$corpus" && sha256sum --check --strict "$$manifest"); \
	tmp=$$(mktemp -d /tmp/mathlib-catalog.XXXXXXXX); trap 'rm -rf -- "$$tmp"' EXIT; \
	catalog="$(abspath $(BUILD_DIR))/mathlib-catalog"; olean="$(abspath $(BUILD_DIR))/mathlib-olean"; \
	prefix=$$("$(LEAN)" --print-prefix); libdir="$$prefix/lib/lean"; \
	export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
	$(CC) $(LDFLAGS) -o "$$tmp/names" "$(BUILD_DIR)/ltar_corpus_names.o" \
	    -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	mkdir "$$tmp/cache"; set --; \
	while read -r digest file; do \
	    ln -s -- "$$corpus/$$file" "$$tmp/cache/$$file"; set -- "$$@" "$$tmp/cache/$$file"; \
	done < "$$manifest"; \
	"$$catalog" build "$$tmp/index" "$$@"; \
	"$$catalog" stats "$$tmp/index" > "$$tmp/stats"; \
	printf 'archives\t13\ndeclarations\t1804\nunqueryable\t0\n' | cmp - "$$tmp/stats"; \
	tab=$$(printf '\t'); decls=0; terms=0; \
	while read -r digest file; do \
	    archive="$$tmp/cache/$$file"; ref="$$tmp/ref-$$file"; mkdir "$$ref"; \
	    "$(LEANTAR)" --jobs 1 -f -C "$$ref" -x "$$archive"; \
	    module=$$(find "$$ref" -type f -name '*.olean'); test -f "$$module"; \
	    "$$tmp/names" "$$module" > "$$tmp/$$file.names"; set --; \
	    awk -v path="$$archive" 'BEGIN{FS=OFS="\t"} {print $$1,$$2,path}' \
	        "$$tmp/$$file.names" > "$$tmp/want"; \
	    while IFS="$$tab" read -r kind name; do \
	        set -- "$$@" "$$name"; decls=$$((decls + 1)); \
	        if test "$$kind" = theorem; then \
	            "$$olean" --term "$$module" "$$name" > "$$tmp/ref-term"; \
	            "$$catalog" term "$$tmp/index" "$$name" > "$$tmp/out"; \
	            cmp "$$tmp/ref-term" "$$tmp/out"; cat "$$tmp/out" >> "$$tmp/proofs"; \
	            terms=$$((terms + 1)); \
	        fi; \
	    done < "$$tmp/$$file.names"; \
	    printf 'missing\tStageSevenMissingDeclaration\n' >> "$$tmp/want"; \
	    status=0; "$$catalog" lookup "$$tmp/index" "$$@" StageSevenMissingDeclaration \
	        > "$$tmp/out" || status=$$?; test "$$status" -eq 1; \
	    cmp "$$tmp/want" "$$tmp/out"; cat "$$tmp/out" >> "$$tmp/lookups"; \
	done < "$$manifest"; \
	test "$$decls/$$terms" = '1804/61'; test "$$(wc -l < "$$tmp/proofs")" -eq 5292; \
	awk 'BEGIN{FS=OFS="\t"} NF==3{sub(/^.*\//,"",$$3)} {print}' "$$tmp/lookups" > "$$tmp/portable"; \
	(cd "$$tmp" && printf '%s  %s\n' \
	    b56d1502ce752552bd3e4f18848eb87d5b4b213066a88cdbffb9748285ea0975 portable \
	    ee8d3d6126fcde424d5fa750ef65b949d3c55987827e64877be9eb83a74628b2 proofs | sha256sum -c -); \
	file='0ecfd22f815cc1b7.ltar'; first="$$tmp/cache/$$file"; copy="$$tmp/copy.ltar"; cp -- "$$first" "$$copy"; \
	for precedence in original copy; do \
	    if test "$$precedence" = original; then winner="$$first"; other="$$copy"; \
	    else winner="$$copy"; other="$$first"; fi; \
	    "$$catalog" build "$$tmp/duplicates" "$$winner" "$$other"; \
	    awk -v path="$$winner" 'BEGIN{FS=OFS="\t"} {print $$1,$$2,path}' "$$tmp/$$file.names" > "$$tmp/want"; \
	    set --; while IFS="$$tab" read -r kind name; do set -- "$$@" "$$name"; done < "$$tmp/$$file.names"; \
	    "$$catalog" lookup "$$tmp/duplicates" "$$@" > "$$tmp/out"; cmp "$$tmp/want" "$$tmp/out"; \
	done; \
	printf '\000additional comment\000' >> "$$copy"; status=0; \
	"$$catalog" term "$$tmp/duplicates" Set.ext > "$$tmp/out" 2> "$$tmp/err" || status=$$?; \
	test "$$status" -eq 2; test ! -s "$$tmp/out"; grep -Fq 'differs from indexed snapshot' "$$tmp/err"; \
	printf '%s\n' '13 archives, 1804 declarations, 13 misses, 61 theorem graphs, duplicate order and freshness passed'
