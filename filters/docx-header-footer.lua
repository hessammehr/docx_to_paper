-- docx-header-footer.lua
-- Pandoc's docx reader ignores page headers/footers. Read the default header
-- and footer of the (last) section and expose them as metadata:
--   header-left / header-center / header-right   (text split on tab stops)
--   footer-left / footer-center / footer-right   (PAGE fields -> \thepage)
--   docx-page-style: true   (page style follows Word: no header/footer or page
--                            numbers unless the document has them)
-- Only fills keys that are not already set in the document metadata.

local function unzip(input, member)
  local ok, out = pcall(pandoc.pipe, 'unzip', {'-p', input, member}, '')
  if ok and out and out ~= '' then return out end
  return nil
end

local function xml_unescape(s)
  local entities = { amp='&', lt='<', gt='>', quot='"', apos="'" }
  s = s:gsub('&#x(%x+);', function(h) return utf8.char(tonumber(h, 16)) end)
  s = s:gsub('&#(%d+);', function(d) return utf8.char(tonumber(d)) end)
  return (s:gsub('&(%a+);', function(e) return entities[e] or ('&' .. e .. ';') end))
end

-- Returns list of tab-separated segments (each a list of pandoc Inlines).
local function parse_part(xml)
  local para = xml:match('<w:p[ >].-</w:p>')
  if not para then return nil end
  local segs, cur = {}, {}
  local in_field_code = false
  local has_text = false
  -- walk tokens in document order
  for tok in para:gmatch('<w:[^>]+>[^<]*') do
    local tagname = tok:match('^<w:([%a]+)')
    if tagname == 'tab' and not tok:match('^<w:tabs') and not tok:match('w:pos=') then
      table.insert(segs, cur); cur = {}
    elseif tagname == 'fldChar' then
      local ty = tok:match('w:fldCharType="(%a+)"')
      if ty == 'begin' then in_field_code = true
      elseif ty == 'separate' or ty == 'end' then in_field_code = false end
    elseif tagname == 'instrText' then
      local instr = tok:match('>([^<]*)') or ''
      if instr:match('PAGE') and not instr:match('NUMPAGES') then
        table.insert(cur, pandoc.RawInline('latex', '\\thepage'))
        has_text = true
      end
    elseif tagname == 't' and not in_field_code then
      local txt = xml_unescape(tok:match('>([^<]*)') or '')
      if txt ~= '' then
        -- a field's cached result (e.g. "2" for PAGE) must be skipped
        table.insert(cur, pandoc.Str(txt)); has_text = true
      end
    end
  end
  table.insert(segs, cur)
  if not has_text then return nil end
  local jc = para:match('<w:pPr>.-<w:jc w:val="(%a+)"')
  return segs, jc
end

-- Skip cached field results: text between fldChar separate and end.
local function strip_field_results(xml)
  return (xml:gsub('<w:fldChar w:fldCharType="separate"/>.-<w:fldChar w:fldCharType="end"/>',
                   '<w:fldChar w:fldCharType="end"/>'))
end

local function assign(meta, prefix, segs, jc)
  local keys
  if #segs == 1 then
    local pos = ({left='left', start='left', right='right', ['end']='right'})[jc or ''] or 'center'
    if jc == nil then pos = 'left' end            -- Word default alignment
    keys = {prefix .. '-' .. pos}
  elseif #segs == 2 then keys = {prefix .. '-left', prefix .. '-right'}
  else keys = {prefix .. '-left', prefix .. '-center', prefix .. '-right'} end
  for i, k in ipairs(keys) do
    local inl = segs[i]
    if i == #keys and #segs > #keys then       -- merge any extra segments
      for j = i + 1, #segs do
        table.insert(inl, pandoc.Space())
        for _, x in ipairs(segs[j]) do table.insert(inl, x) end
      end
    end
    if meta[k] == nil and inl and #inl > 0 then meta[k] = pandoc.MetaInlines(inl) end
  end
end

function Pandoc(doc)
  local input = PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if not input or not input:match('%.docx$') then return doc end
  local docxml = unzip(input, 'word/document.xml')
  local rels = unzip(input, 'word/_rels/document.xml.rels')
  if not docxml or not rels then return doc end

  if doc.meta['docx-page-style'] == nil then
    doc.meta['docx-page-style'] = true
  end

  local sect = docxml:match('.*(<w:sectPr.-</w:sectPr>)') or ''
  for _, kind in ipairs({'header', 'footer'}) do
    local rid = sect:match('<w:' .. kind .. 'Reference[^>]-w:type="default"[^>]-r:id="([^"]+)"')
             or sect:match('<w:' .. kind .. 'Reference[^>]-r:id="([^"]+)"[^>]-w:type="default"')
    if rid then
      local target = rels:match('Id="' .. rid .. '"[^>]-Target="([^"]+)"')
                  or rels:match('Target="([^"]+)"[^>]-Id="' .. rid .. '"')
      local xml = target and unzip(input, 'word/' .. target)
      if xml then
        local segs, jc = parse_part(strip_field_results(xml))
        if segs then assign(doc.meta, kind, segs, jc) end
      end
    end
  end
  return doc
end
