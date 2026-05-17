-- Remove CSL JSON references embedded by pandoc's docx+citations reader.
-- Use this only when writing Markdown after separately exporting a .bib file.

function Pandoc(doc)
  doc.meta.references = nil
  return doc
end
