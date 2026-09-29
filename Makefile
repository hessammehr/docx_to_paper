# General DOCX/Markdown -> proposal PDF workflow.
#
# Drop one or more Zotero-cited .docx files in this folder and run:
#   make                 # extract Markdown/BibLaTeX and build PDFs
#   make extract         # only create build/<name>/<name>.md and .bib
#   make pdf             # build PDFs from extracted Markdown
#   make docx            # round-trip extracted Markdown back to DOCX
#   make tex             # emit intermediate LaTeX for debugging
#   make clean
#
# Existing .md files in this folder, except README.md, are also built to PDF.

SHELL := /bin/bash

TEMPLATE := template.tex
CSL      := example.csl
FILTER   := readable-citekeys.lua
DROP_REFS_FILTER := drop-embedded-references.lua
CORE_PROPS_FILTER := docx-core-props.lua
ZOTERO_CHECK_FILTER := zotero-check.lua
BUILD    := build

PANDOC        := pandoc
PANDOC_ENGINE ?= xelatex

# Ignore Word lock files (~$foo.docx). GNU make is not pleasant with spaces in
# target names; use simple filenames for dropped-in DOCX files if possible.
DOCX := $(filter-out ~$%,$(wildcard *.docx))
DOCX_BASE := $(basename $(DOCX))
ROOT_MD := $(filter-out README.md,$(wildcard *.md))

DOCX_MD    := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name).md)
DOCX_BIB   := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name).bib)
DOCX_JSON  := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name).json)
DOCX_PDF   := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name).pdf)
DOCX_TEX   := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name).tex)
DOCX_DOCX  := $(foreach name,$(DOCX_BASE),$(BUILD)/$(name)/$(name)-roundtrip.docx)
ROOT_PDF   := $(ROOT_MD:.md=.pdf)

COMMON_PDF_FLAGS := \
	--from=markdown \
	--template=$(TEMPLATE) \
	--citeproc \
	--csl=$(CSL) \
	--pdf-engine=$(PANDOC_ENGINE)

.PHONY: all extract pdf docx tex root-pdf clean watch list

all: extract pdf

extract: $(DOCX_MD) $(DOCX_BIB) $(DOCX_JSON)

pdf: $(DOCX_PDF) root-pdf

docx: $(DOCX_DOCX)

tex: $(DOCX_TEX)

root-pdf: $(ROOT_PDF)

list:
	@echo "DOCX:     $(DOCX)"
	@echo "ROOT_MD:  $(ROOT_MD)"
	@echo "DOCX_MD:  $(DOCX_MD)"
	@echo "DOCX_BIB: $(DOCX_BIB)"
	@echo "DOCX_JSON: $(DOCX_JSON)"
	@echo "DOCX_PDF: $(DOCX_PDF)"

# Extract Markdown, BibLaTeX and CSL-JSON from each Zotero-cited Word document.
# The Lua filter replaces Zotero numeric IDs with readable citation keys in all
# three. The PDF uses the CSL-JSON: it keeps Zotero's item types (e.g. preprints),
# which the BibLaTeX round-trip loses. The .bib is an editable export.
# Explicit per-file rules avoid GNU make's awkwardness with repeated % patterns.
define DOCX_RULES
$(BUILD)/$(1)/$(1).md $(BUILD)/$(1)/$(1).bib $(BUILD)/$(1)/$(1).json: $(1).docx $(FILTER) $(DROP_REFS_FILTER) $(CORE_PROPS_FILTER) $(ZOTERO_CHECK_FILTER)
	@mkdir -p $(BUILD)/$(1)
	$(PANDOC) -f docx+citations \
		--lua-filter=$(FILTER) \
		--lua-filter=$(DROP_REFS_FILTER) \
		--lua-filter=$(CORE_PROPS_FILTER) \
		--lua-filter=$(ZOTERO_CHECK_FILTER) \
		"$(1).docx" \
		-t markdown --standalone --extract-media=$(BUILD)/$(1) \
		-M bibliography=$(1).bib \
		-M csl=../../$(CSL) \
		-M suppress-bibliography=true \
		-o $(BUILD)/$(1)/$(1).md
	$(PANDOC) -f docx+citations --lua-filter=$(FILTER) "$(1).docx" \
		-t biblatex \
		-o $(BUILD)/$(1)/$(1).bib
	$(PANDOC) -f docx+citations --lua-filter=$(FILTER) "$(1).docx" \
		-t csljson \
		-o $(BUILD)/$(1)/$(1).json
	@# Zotero stores arXiv numbers as "arXiv:NNNN"; CSL styles add their own prefix.
	perl -pi -e 's/("number":\s*")arXiv:/$$$$1/' $(BUILD)/$(1)/$(1).json

# LaTeX cannot include SVG directly unless the local toolchain provides SVG
# conversion. For PDF output only, make a Markdown copy whose SVG links point to
# vector PDFs made with rsvg-convert or Inkscape. DOCX/Markdown keep the SVGs.
$(BUILD)/$(1)/$(1)-pdf.md: $(BUILD)/$(1)/$(1).md
	@cp "$$<" "$$@"
	@if find $(BUILD)/$(1)/media -name '*.svg' -print -quit | grep -q .; then \
		echo "Converting SVG media to vector PDF for LaTeX: $(BUILD)/$(1)/media"; \
		find $(BUILD)/$(1)/media -name '*.svg' -print0 | while IFS= read -r -d '' svg; do \
			pdf="$$$${svg%.svg}.pdf"; \
			if command -v rsvg-convert >/dev/null 2>&1; then \
				rsvg-convert -f pdf "$$$$svg" -o "$$$$pdf"; \
			elif command -v inkscape >/dev/null 2>&1; then \
				inkscape "$$$$svg" --export-type=pdf --export-filename="$$$$pdf"; \
			else \
				echo "Need rsvg-convert or inkscape to convert $$$$svg to vector PDF" >&2; exit 1; \
			fi; \
		done; \
		perl -0pi -e 's/\.svg(?=([\)"{]))/.pdf/g' "$$@"; \
	fi

$(BUILD)/$(1)/$(1).pdf: $(BUILD)/$(1)/$(1)-pdf.md $(BUILD)/$(1)/$(1).json $(TEMPLATE) $(CSL)
	$(PANDOC) $(COMMON_PDF_FLAGS) \
		--bibliography=$(BUILD)/$(1)/$(1).json \
		-M suppress-bibliography=true \
		-o "$$@" "$$<"

$(BUILD)/$(1)/$(1).tex: $(BUILD)/$(1)/$(1)-pdf.md $(BUILD)/$(1)/$(1).json $(TEMPLATE) $(CSL)
	$(PANDOC) $(COMMON_PDF_FLAGS) \
		--bibliography=$(BUILD)/$(1)/$(1).json \
		-M suppress-bibliography=true \
		-o "$$@" "$$<"

$(BUILD)/$(1)/$(1)-roundtrip.docx: $(BUILD)/$(1)/$(1).md $(BUILD)/$(1)/$(1).bib
	$(PANDOC) --from=markdown --citeproc \
		--bibliography=$(BUILD)/$(1)/$(1).bib \
		-o "$$@" "$$<"
endef

$(foreach name,$(DOCX_BASE),$(eval $(call DOCX_RULES,$(name))))

# Backwards-compatible rule for hand-written Markdown in this directory
# (e.g. Abstract.md + Group papers.bib). Bibliography/CSL may be set in YAML;
# if not, pass BIB="file.bib" on the make command line.
%.pdf: %.md $(TEMPLATE) $(CSL)
	$(PANDOC) $(COMMON_PDF_FLAGS) $(if $(BIB),--bibliography="$(BIB)",) -o "$@" "$<"

clean:
	rm -rf $(BUILD)
	rm -f $(ROOT_PDF)

watch:
	@command -v fswatch >/dev/null 2>&1 || { echo "fswatch not installed (brew install fswatch)"; exit 1; }
	@echo "Watching DOCX/MD/template/CSL/filter files..."
	@while true; do \
		$(MAKE) --no-print-directory all; \
		fswatch -1 . >/dev/null; \
	done
