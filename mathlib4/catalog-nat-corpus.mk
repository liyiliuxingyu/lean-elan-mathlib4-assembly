# Optional cross-check of every module under Mathlib/Data/Nat in v4.19.0.
.PHONY: test-catalog-nat-corpus
NAT_ALL_TERMS ?= 0
test-catalog-nat-corpus: $(BUILD_DIR)/mathlib-catalog $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/ltar_corpus_names.o
	@set -eu; export LC_ALL=C; \
	test -n "$(NAT_CORPUS)" || { echo 'set NAT_CORPUS to the pinned archive directory' >&2; exit 1; }; \
	case "$(NAT_ALL_TERMS)" in 0|1) ;; *) echo 'NAT_ALL_TERMS must be 0 or 1' >&2; exit 1 ;; esac; \
	test "$$("$(LEANTAR)" --version)" = 'leantar 0.1.15'; \
	test "$$("$(LEAN)" --githash)" = '6caaee842e9495688c1567e78c0e68dbb96942aa'; \
	manifest="$(abspath catalog-nat-corpus.tsv)"; corpus="$(abspath $(NAT_CORPUS))"; \
	tmp=$$(mktemp -d); trap 'rm -rf -- "$$tmp"' EXIT; \
	catalog="$(abspath $(BUILD_DIR))/mathlib-catalog"; olean="$(abspath $(BUILD_DIR))/mathlib-olean"; \
	awk -F '\t' 'NF != 3 || $$1 !~ /^Mathlib\.Data\.Nat\./ || \
	    $$2 !~ /^[[:xdigit:]]+\.ltar$$/ || length($$2) != 21 || \
	    $$3 !~ /^[[:xdigit:]]+$$/ || length($$3) != 64 || $$1 <= prev || files[$$2]++ { exit 1 } \
	    { prev=$$1; print $$3 "  " $$2 } END { if (NR != 80) exit 1 }' "$$manifest" > "$$tmp/hashes"; \
	(cd "$$corpus" && sha256sum --check --strict --quiet "$$tmp/hashes"); \
	libdir=$$("$(LEAN)" --print-prefix)/lib/lean; \
	export LD_LIBRARY_PATH="$$libdir$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"; \
	$(CC) $(LDFLAGS) -o "$$tmp/stock-names" "$(BUILD_DIR)/ltar_corpus_names.o" \
	    -L"$$libdir" -Wl,-rpath,"$$libdir" -lleanshared; \
	mkdir "$$tmp/cache" "$$tmp/modules" "$$tmp/groups"; tab=$$(printf '\t'); nmodules=0; set --; \
	while IFS="$$tab" read -r mod file digest; do \
	    archive="$$tmp/cache/$$file"; ln -s -- "$$corpus/$$file" "$$archive"; set -- "$$@" "$$archive"; \
	    mkdir "$$tmp/unpacked"; "$(LEANTAR)" --jobs 1 -f -C "$$tmp/unpacked" -x "$$archive"; \
	    rel=$$(printf '%s' "$$mod" | tr . /); module="$$tmp/modules/$$file.olean"; \
	    mv "$$tmp/unpacked/.lake/build/lib/lean/$$rel.olean" "$$module"; rm -rf -- "$$tmp/unpacked"; \
	    "$$tmp/stock-names" "$$module" > "$$tmp/stock"; \
	    awk -F '\t' -v f="$$file" 'NF != 2 || length($$2) == 0 { exit 1 } \
	        { print $$1 "\t" $$2 "\t" f }' "$$tmp/stock" >> "$$tmp/all"; \
	    nmodules=$$((nmodules + 1)); \
	done < "$$manifest"; \
	"$$catalog" build "$$tmp/index" "$$@"; \
	records=$$(wc -l < "$$tmp/all"); "$$catalog" stats "$$tmp/index" > "$$tmp/stats"; \
	printf 'archives\t%s\ndeclarations\t%s\nunqueryable\t0\n' "$$nmodules" "$$records" | cmp - "$$tmp/stats"; \
	awk -F '\t' -v proofs="$$tmp/samples" -v full="$(NAT_ALL_TERMS)" 'BEGIN { OFS=FS } \
	    !($$2 in file) { file[$$2]=$$3; kind[$$2]=$$1; \
	        if ($$1 == "theorem" && (full || !sample[$$3]++ || $$2 == "Nat.unpair_pair" || $$2 == "Nat.pair_unpair")) \
	            print $$1,$$2,$$3 > proofs } \
	    { print kind[$$2],$$2,file[$$2] }' "$$tmp/all" > "$$tmp/winners"; \
	split -l 200 "$$tmp/winners" "$$tmp/groups/queries-"; batches=0; \
	for batch in "$$tmp"/groups/queries-*; do \
	    set --; while IFS="$$tab" read -r kind name file; do set -- "$$@" "$$name"; done < "$$batch"; \
	    awk -F '\t' -v pre="$$tmp/cache/" 'BEGIN{OFS=FS} {print $$1,$$2,pre $$3}' "$$batch" > "$$tmp/want"; \
	    printf 'missing\tNat.StageSevenNatCorpusMissing\n' >> "$$tmp/want"; \
	    status=0; "$$catalog" lookup "$$tmp/index" "$$@" Nat.StageSevenNatCorpusMissing > "$$tmp/out" || status=$$?; \
	    test "$$status" -eq 1; cmp "$$tmp/want" "$$tmp/out"; batches=$$((batches + 1)); \
	done; \
	while IFS="$$tab" read -r kind name file; do \
	    "$$olean" --term "$$tmp/modules/$$file.olean" "$$name" > "$$tmp/want"; \
	    "$$catalog" term "$$tmp/index" "$$name" > "$$tmp/out"; test -s "$$tmp/want"; \
	    cmp "$$tmp/want" "$$tmp/out"; cat "$$tmp/out" >> "$$tmp/proofs"; \
	done < "$$tmp/samples"; \
	pairfile=$$(awk -F '\t' '$$1 == "Mathlib.Data.Nat.Pairing" {print $$2}' "$$manifest"); test -n "$$pairfile"; \
	first="$$tmp/cache/$$pairfile"; copy="$$tmp/pairing-copy"; cp -- "$$first" "$$copy"; \
	for priority in original copy; do \
	    if test "$$priority" = original; then win="$$first"; other="$$copy"; else win="$$copy"; other="$$first"; fi; \
	    "$$catalog" build "$$tmp/dual" "$$win" "$$other"; \
	    "$$catalog" lookup "$$tmp/dual" Nat.pair Nat.unpair Nat.unpair_pair Nat.pair_unpair > "$$tmp/out"; \
	    printf '%s\t%s\t%s\n' definition Nat.pair "$$win" definition Nat.unpair "$$win" \
	        theorem Nat.unpair_pair "$$win" theorem Nat.pair_unpair "$$win" | cmp - "$$tmp/out"; \
	done; \
	unique=$$(cut -f2 "$$tmp/all" | sort -u | wc -l); ntheorems=$$(awk -F '\t' '$$1=="theorem"{n++} END{print n+0}' "$$tmp/all"); \
	printf '%s modules, %s declaration records (%s distinct, %s repeated), %s theorems, %s misses, %s checked graphs (%s lines); duplicate ordering passed\n' \
	    "$$nmodules" "$$records" "$$unique" "$$((records-unique))" "$$ntheorems" "$$batches" \
	    "$$(wc -l < "$$tmp/samples")" "$$(wc -l < "$$tmp/proofs")"; \
	if test "$(NAT_ALL_TERMS)" = 1; then \
	    proofhash=8390a6193a29e24afa5577ac3cd8cf5a0d45f3d073db21b6e79ece42f93d0e09; \
	else proofhash=a5c906dd49c34e0a01bf7d9456070ba3696264a12c108c5ce24f45199ea3d211; fi; \
	(cd "$$tmp" && printf '%s  %s\n' \
	    ac22bf2c648d82a4cb7c3e211872210523f9a4758c1b889f3826bfe95f1a7818 winners \
	    "$$proofhash" proofs | sha256sum --check --strict -)
