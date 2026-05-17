# docx_to_paper

A small Pandoc/Make workflow for turning Zotero-cited Word documents into editable Markdown, a BibLaTeX bibliography, and a PDF built with a LaTeX template and CSL style.

## What it does

Drop one or more `.docx` files into this directory and run:

```sh
make
```

For each `paper.docx`, the workflow creates:

```text
build/paper/paper.md      # standalone Markdown with YAML front matter
build/paper/paper.bib     # bibliography extracted from Zotero citations
build/paper/paper.pdf     # PDF built via Pandoc + LaTeX
build/paper/media/        # extracted media
```

The Markdown uses Pandoc citations such as:

```markdown
[@Kemppinen2020; @Qi2016]
```

rather than Zotero numeric IDs. Existing Better BibTeX citation keys are preserved when available; otherwise keys are generated as `FirstAuthorYear`.

## Requirements

- `pandoc` with Lua support
- GNU/BSD `make`
- A LaTeX engine, default `xelatex`
- For SVG figures in PDFs: `rsvg-convert` or `inkscape`

On macOS with Homebrew, for example:

```sh
brew install pandoc librsvg inkscape
```

Install a TeX distribution separately, e.g. MacTeX or TinyTeX.

## Usage

```sh
make          # extract Markdown/BibLaTeX and build PDFs
make extract  # only create build/<name>/<name>.md and .bib
make pdf      # build PDFs from extracted Markdown
make docx     # round-trip extracted Markdown back to DOCX
make tex      # emit intermediate LaTeX for debugging
make list     # show detected inputs and outputs
make clean
```

You can change the PDF engine:

```sh
make PANDOC_ENGINE=lualatex
```

## Files to customize

- `template.tex` — LaTeX template for PDF output
- `example.csl` — CSL citation style
- `Makefile` — build rules and Pandoc options

## Notes

- Input `.docx` filenames should avoid spaces if possible; Makefile targets with spaces are awkward.
- Zotero citations must be live Word fields. Flattened/plain-text citations cannot be recovered as structured citations.
- Extracted Markdown preserves SVG figures. For PDF output only, SVGs are converted to vector PDF for LaTeX; they are not rasterized.
- `docx-core-props.lua` reads Word core properties and fills missing YAML metadata such as `author` from `dc:creator`.
