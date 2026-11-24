# Optional real-cache differential. LTAR_CORPUS contains the pinned 13 archives.
LEANTAR ?= leantar
.PHONY: test-ltar-corpus
test-ltar-corpus: $(BUILD_DIR)/mathlib-ltar $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/ltar_corpus_names.o
	@set -eu; \
	test -n "$(LTAR_CORPUS)" || { echo 'set LTAR_CORPUS to the cache archive directory' >&2; exit 1; }; \
	test "$$("$(LEANTAR)" --version)" = 'leantar 0.1.15'; \
	test "$$("$(LEAN)" --githash)" = 6caaee842e9495688c1567e78c0e68dbb96942aa; \
	manifest="$(abspath ltar-corpus.sha256)"; corpus="$(abspath $(LTAR_CORPUS))"; \
	(cd "$$corpus" && sha256sum --check --strict "$$manifest"); \
	tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; \
	prefix=$$("$(LEAN)" --print-prefix); libdir="$$prefix/lib/lean"; \
	export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
	$(CC) $(LDFLAGS) -o "$$tmp/names" "$(BUILD_DIR)/ltar_corpus_names.o" \
	  -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	mkdir "$$tmp/ref"; tab=$$(printf '\t'); members=0; decls=0; terms=0; \
	while read -r digest file; do \
	  archive="$$corpus/$$file"; "$(LEANTAR)" --jobs 1 -f -C "$$tmp/ref" -x "$$archive"; \
	  "$(BUILD_DIR)/mathlib-ltar" --list "$$archive" > "$$tmp/list"; module=; \
	  while IFS="$$tab" read -r kind offset size member; do \
	    "$(BUILD_DIR)/mathlib-ltar" --cat "$$archive" "$$member" > "$$tmp/out"; \
	    cmp "$$tmp/ref/$$member" "$$tmp/out"; members=$$((members+1)); \
	    case "$$member" in *.olean) module="$$tmp/ref/$$member";; esac; \
	  done < "$$tmp/list"; \
	  "$$tmp/names" "$$module" > "$$tmp/expected"; set --; \
	  while IFS="$$tab" read -r kind name; do \
	    set -- "$$@" "$$name"; decls=$$((decls+1)); \
	    if test "$$kind" = theorem; then \
	      "$(BUILD_DIR)/mathlib-olean" --term "$$module" "$$name" > "$$tmp/expanded"; \
	      "$(BUILD_DIR)/mathlib-ltar" --term "$$archive" "$$name" > "$$tmp/out"; \
	      cmp "$$tmp/expanded" "$$tmp/out"; cat "$$tmp/out" >> "$$tmp/proofs"; terms=$$((terms+1)); \
	    fi; \
	  done < "$$tmp/expected"; \
	  printf 'missing\tStageSixMissingDeclaration\n' >> "$$tmp/expected"; status=0; \
	  "$(BUILD_DIR)/mathlib-ltar" --lookup "$$archive" "$$@" StageSixMissingDeclaration > "$$tmp/out" || status=$$?; \
	  test "$$status" -eq 1; cmp "$$tmp/expected" "$$tmp/out"; cat "$$tmp/out" >> "$$tmp/lookups"; \
	done < "$$manifest"; \
	test "$$members/$$decls/$$terms" = '91/1804/61'; test "$$(wc -l < "$$tmp/proofs")" -eq 5292; \
	(cd "$$tmp" && printf '%s  %s\n' \
	  4030f61b4773e2695664f2b7ef02f21e796470dc4d08152451e6d3cf90553d86 lookups \
	  ee8d3d6126fcde424d5fa750ef65b949d3c55987827e64877be9eb83a74628b2 proofs | sha256sum -c -); \
	printf '%s\n' '13 archives, 91 payloads, 1,804 declarations, 13 misses and 61 theorem graphs passed'
