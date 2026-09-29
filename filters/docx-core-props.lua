-- Add DOCX core properties that Pandoc's docx reader does not expose.
-- In particular, map docProps/core.xml dc:creator -> author when author is
-- missing. Also fills title/date from core props if Pandoc did not infer them.

local function trim(s)
  return (s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function xml_unescape(s)
  s = s or ''
  local entities = { amp='&', lt='<', gt='>', quot='"', apos="'" }
  s = s:gsub('&(#x%x+);', function(h) return utf8.char(tonumber(h:sub(3), 16)) end)
  s = s:gsub('&(#%d+);', function(d) return utf8.char(tonumber(d:sub(2), 10)) end)
  s = s:gsub('&([A-Za-z]+);', function(e) return entities[e] or '&' .. e .. ';' end)
  return s
end

local function tag(xml, name)
  return trim(xml_unescape(xml:match('<' .. name .. '[^>]*>(.-)</' .. name .. '>')))
end

local function is_empty_meta(v)
  return v == nil or pandoc.utils.stringify(v) == ''
end

function Pandoc(doc)
  local input = PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if not input or not input:match('%.docx$') then return doc end

  local ok, xml = pcall(pandoc.pipe, 'unzip', {'-p', input, 'docProps/core.xml'}, '')
  if not ok or not xml or xml == '' then return doc end

  local creator = tag(xml, 'dc:creator')
  local title = tag(xml, 'dc:title')
  local created = tag(xml, 'dcterms:created')

  if creator ~= '' and is_empty_meta(doc.meta.author) then
    doc.meta.author = creator
  end
  if title ~= '' and is_empty_meta(doc.meta.title) then
    doc.meta.title = title
  end
  if created ~= '' and is_empty_meta(doc.meta.date) then
    doc.meta.date = created:gsub('T.*$', '')
  end

  return doc
end
