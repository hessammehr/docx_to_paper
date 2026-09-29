-- colors.lua
--
-- PDF stage only. Render the colour spans written by docx-colors.lua (or by
-- hand in Markdown):
--
--   [text]{color="#BF4E14"}    -> \textcolor
--   [text]{shading="#FAE2D5"}  -> \highLight (lua-ul), which breaks across
--                                 lines like Word's shading
--
-- Shading needs LuaLaTeX (the default engine); with other engines the
-- template drops it and keeps the text colour.

local function hex(v)
  return v and v:match('^#?(%x%x%x%x%x%x)$')
end

function Span(el)
  if not FORMAT:match('latex') then return nil end
  local color, fill = hex(el.attributes.color), hex(el.attributes.shading)
  if not color and not fill then return nil end
  local out = pandoc.Inlines(el.content)
  if color then
    out:insert(1, pandoc.RawInline('latex', '\\textcolor[HTML]{' .. color:upper() .. '}{'))
    out:insert(pandoc.RawInline('latex', '}'))
  end
  if fill then
    local name = 'docxshade' .. fill:upper()
    out:insert(1, pandoc.RawInline('latex', '\\definecolor{' .. name .. '}{HTML}{'
      .. fill:upper() .. '}\\highLight[' .. name .. ']{'))
    out:insert(pandoc.RawInline('latex', '}'))
  end
  el.attributes.color, el.attributes.shading = nil, nil
  el.content = out
  return el
end
