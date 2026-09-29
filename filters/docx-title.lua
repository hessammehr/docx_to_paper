-- docx-title.lua
--
-- If the document has no title and starts with an image-only paragraph followed
-- by a short text paragraph, treat them as title graphic and title:
--   titlegraphic: <the image, at its Word size>     title: <paragraph text>
-- Both paragraphs are removed from the body. Word's own "Title" style is
-- already mapped to the title by pandoc and takes precedence.

local stringify = pandoc.utils.stringify

function Pandoc(doc)
  if doc.meta.title and stringify(doc.meta.title) ~= '' then return doc end
  local b1, b2 = doc.blocks[1], doc.blocks[2]
  if not (b1 and b2) then return doc end
  local is_image_para = (b1.t == 'Para' or b1.t == 'Plain')
    and #b1.content == 1 and b1.content[1].t == 'Image'
  local is_title_para = (b2.t == 'Para' or b2.t == 'Plain')
    and #stringify(b2) > 0 and #stringify(b2) < 120
  if is_image_para and is_title_para then
    doc.meta.title = pandoc.MetaInlines(b2.content)
    doc.meta.titlegraphic = pandoc.MetaInlines({b1.content[1]})
    doc.blocks:remove(1)
    doc.blocks:remove(1)
  end
  return doc
end
