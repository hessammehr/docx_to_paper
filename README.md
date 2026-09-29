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
build/paper/paper.bib     # BibLaTeX export of the Zotero citations (for editing/reuse)
build/paper/paper.json    # CSL-JSON of the Zotero citations (used for the PDF)
build/paper/paper.pdf     # PDF built via Pandoc + LaTeX
build/paper/media/        # extracted media
```

The Markdown uses Pandoc citations such as:

```markdown
[@Kemppinen2020; @Qi2016]
```

rather than Zotero numeric IDs. Existing Better BibTeX citation keys are preserved when available; otherwise keys are generated as `FirstAuthorYear`, with accented letters transliterated (`Gonçalves` → `Goncalves2020`).

The PDF bibliography comes from the CSL-JSON export, which keeps Zotero's item types exactly (e.g. arXiv/ChemRxiv preprints). Converting to BibLaTeX loses some of these, so the `.bib` is only an editable export.

## Requirements

- `pandoc` with Lua support
- GNU/BSD `make`
- A LaTeX engine, default `lualatex` (`xelatex` and `pdflatex` also work)
- TeX packages `libertine`, `newtx` and `inconsolata` (all in TeX Live/MacTeX)
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
make PANDOC_ENGINE=xelatex
```

## Files to customize

- `template.tex` — LaTeX template for PDF output (see below)
- `example.csl` — CSL citation style
- `Makefile` — build rules and Pandoc options

Lua filters live in `filters/`. These run when extracting from DOCX:

- `readable-citekeys.lua` — readable citation keys
- `drop-embedded-references.lua` — keeps the Markdown free of embedded CSL data
- `docx-core-props.lua` — fills `author`/`title`/`date` from Word core properties
- `docx-header-footer.lua` — copies Word's page header and footer (see below)
- `docx-title.lua` — a leading image + short paragraph becomes `titlegraphic` + `title`
- `zotero-check.lua` — warns about unresolved Zotero citations (see below)

and when building the PDF:

- `stray-superscripts.lua` — drops and reports leftover citation numbers
- `center-images.lua` — centres images that stand alone in a paragraph, as Word does

## Template

`template.tex` sets Linux Libertine text with `newtxmath` maths and Inconsolata for code, similar in look to ACM/SIGGRAPH papers. It uses Pandoc's built-in `common.latex` partial for lists, tables, graphics and citations. Section numbers are not generated; headings keep whatever numbering they have in Word. Options, set in the YAML front matter or with `-M key=value`:

| Variable | Default | Effect |
|---|---|---|
| `fontsize` | `10pt` | Base font size (`10pt`, `11pt`, `12pt`) |
| `papersize` | `a4` | Paper size (`a4`, `letter`, ...) |
| `geometry` | `margin=2.2cm` | Options for the `geometry` package |
| `twocolumn` | off | Two-column layout |
| `indent` | off | Indented paragraphs instead of spaced ones |
| `byline` | off | Print `author`/`date` under the title |
| `titlegraphic` | – | Image shown above the title |
| `linestretch`, `lang` | – | As in Pandoc's default template |

For DOCX input, the page style follows the Word document: the header and footer text are copied (split at tab stops into left/centre/right) and page numbers appear only where Word has a PAGE field. Nothing else is added: no title unless the document has one, and no author/date line unless `byline` is set. Hand-written Markdown gets LaTeX's default page numbers.

## Notes

- Input `.docx` filenames should avoid spaces if possible; Makefile targets with spaces are awkward.
- Zotero citations must be live Word fields. Flattened/plain-text citations cannot be recovered as structured citations.
- `[zotero-check]` warnings point to citations Zotero never finished inserting (`ZOTERO_TEMP` fields, often shown as `{Citation}` or a bare number in Word). Pandoc drops some of these silently. Re-insert them with Zotero and save.
- `[stray-superscripts]` warnings list superscript numbers that look like citations but are plain text (e.g. typed or pasted `^8,9^`). They are removed from the PDF because they would clash with the generated numbering. Exponents such as `x^2^`, `10^6^` or `cm^-1^` are kept.
- Extracted Markdown preserves SVG figures. For PDF output only, SVGs are converted to vector PDF for LaTeX; they are not rasterized.
- `docx-core-props.lua` reads Word core properties and fills missing YAML metadata such as `author` from `dc:creator`.
