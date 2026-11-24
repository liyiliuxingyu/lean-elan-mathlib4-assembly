# SPDX-License-Identifier: Apache-2.0
.PHONY: test-metadata-graph

test-term: test-metadata-graph

test-metadata-graph: $(BUILD_DIR)/mathlib-olean $(BUILD_DIR)/olean_metadata_fixture.o
	@set -eu; \
	scratch=$$(mktemp -d); \
	trap 'rm -rf -- "$$scratch"' EXIT; \
	fixture="$(BUILD_DIR)/olean_metadata_fixture.o"; \
	$(OBJCOPY) -O binary -j .meta_fixture "$$fixture" "$$scratch/Meta.olean"; \
	$(OBJCOPY) -O binary -j .meta_graph_expected "$$fixture" "$$scratch/expected"; \
	"$(BUILD_DIR)/mathlib-olean" --term "$$scratch/Meta.olean" cacheMetaFixture > "$$scratch/actual"; \
	LC_ALL=C sort "$$scratch/expected" > "$$scratch/expected.sorted"; \
	LC_ALL=C sort "$$scratch/actual" > "$$scratch/actual.sorted"; \
	cmp "$$scratch/expected.sorted" "$$scratch/actual.sorted"; \
	printf '%s\n' 'olean metadata graph tests passed'
