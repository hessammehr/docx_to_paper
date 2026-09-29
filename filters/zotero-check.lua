-- zotero-check.lua
--
-- Report unresolved Zotero placeholder fields (ADDIN ZOTERO_TEMP) in a DOCX.
-- Word stores fields either as fldChar/instrText runs or as fldSimple; pandoc
-- drops the fldSimple form silently, so these would otherwise go unnoticed.
-- Changes nothing; only writes warnings to stderr.

local function context(xml, pos)
  local before = xml:sub(math.max(1, pos - 3000), pos)
  local txt = before:gsub('<w:instrText.-</w:instrText>', '')
                    :gsub('<[^>]+>', '')
                    :gsub('<[^>]*$', '')
  return txt:sub(-60)
end

function Pandoc(doc)
  local input = PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if not input or not input:match('%.docx$') then return doc end

  local ok, xml = pcall(pandoc.pipe, 'unzip', {'-p', input, 'word/document.xml'}, '')
  if not ok or not xml or xml == '' then return doc end

  local positions = {}
  for pos in xml:gmatch('()<w:fldSimple w:instr="%s*ADDIN ZOTERO_TEMP') do
    table.insert(positions, pos)
  end
  for pos in xml:gmatch('()<w:instrText[^>]*>%s*ADDIN ZOTERO_TEMP') do
    table.insert(positions, pos)
  end
  table.sort(positions)

  for _, pos in ipairs(positions) do
    io.stderr:write(('[zotero-check] %s: unresolved Zotero citation after "...%s"\n')
      :format(input, context(xml, pos)))
  end
  if #positions > 0 then
    io.stderr:write(('[zotero-check] %s: %d unresolved citation(s); re-insert them with Zotero in Word.\n')
      :format(input, #positions))
  end
  return doc
end
