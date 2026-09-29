-- docx-colors.lua
--
-- Pandoc's docx reader drops direct character formatting: font colour
-- (<w:color>) and run shading (<w:shd>). This filter reads word/document.xml
-- from the input .docx (read-only, via unzip -p) and puts both back as spans:
--
--   [text]{color="#BF4E14"}      [text]{shading="#FAE2D5"}
--
-- e.g. a shaded stretch that starts with a coloured bold label becomes
--
--   [**[Samples:]{color="#BF4E14"} W0.** Initial batch ...]{shading="#FAE2D5"}
--
-- The spans stay in the extracted Markdown; filters/colors.lua renders them
-- in the PDF. Word runs are matched to pandoc's text character by character
-- (ignoring whitespace), so spans may start or end mid-word or cross bold and
-- italic; where they cross, they are split into adjacent pieces.
--
-- Left alone, as usually accidental: black/dark grey text, white shading,
-- and stretches without a letter or digit (e.g. a coloured ", ").
-- Not handled: colours from character styles, highlighter pen (pandoc keeps it
-- as [text]{.mark}), table-cell shading, text in headers/footers, footnotes
-- and text boxes. Paragraphs whose text pandoc changed (e.g. symbol fonts) are
-- reported on stderr and left uncoloured.

-- Word runs ---------------------------------------------------------------

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

-- Text with whitespace (incl. no-break space) removed: the unit of alignment.
local function squash(s)
  return (s:gsub('\xC2\xA0', ''):gsub('%s', ''))
end

local function nchars(s)
  local t = squash(s)
  return utf8.len(t) or #t
end

local function hex_rgb(h)
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end

-- Black or dark grey: ordinary text colour (e.g. pasted from the web).
local function is_text_colour(h)
  local r, g, b = hex_rgb(h)
  return math.max(r, g, b) - math.min(r, g, b) < 16 and math.max(r, g, b) < 0x60
end

local function run_format(run)
  local rpr = (run:match('<w:rPr>(.-)</w:rPr>') or '')
  local color = rpr:match('<w:color [^>]-w:val="(%x%x%x%x%x%x)"')
  if color and is_text_colour(color) then color = nil end
  local shd = rpr:match('<w:shd [^>]*>') or ''
  local fill = shd:match('w:fill="(%x%x%x%x%x%x)"')
  if shd:match('w:val="solid"') then fill = shd:match('w:color="(%x%x%x%x%x%x)"') or fill end
  if fill and fill:upper() == 'FFFFFF' then fill = nil end
  return { color = color and color:upper(), shading = fill and fill:upper() }
end

local function run_text(run)
  local parts = {}
  for txt in run:gmatch('<w:t%f[ >][^>]*>([^<]*)</w:t>') do
    table.insert(parts, xml_unescape(txt))
  end
  return table.concat(parts)
end

-- Stretches of consecutive runs with the same colour (or shading), as
-- [from, to) offsets into the paragraph's squashed text.
local function paragraph_stretches(para)
  local text, pos, out, open = {}, 0, {}, {}
  local function close(kind)
    local s = open[kind]
    if s and s.text:match('[%w\128-\255]') then table.insert(out, s) end
    open[kind] = nil
  end
  for run in para:gmatch('<w:r[ >].-</w:r>') do
    local t = run_text(run)
    local n = nchars(t)
    table.insert(text, t)
    if n > 0 then
      local fmt = run_format(run)
      for _, kind in ipairs({'shading', 'color'}) do
        local v, s = fmt[kind], open[kind]
        if s and s.value == v and s.to == pos then
          s.to, s.text = pos + n, s.text .. t
        else
          close(kind)
          if v then open[kind] = { kind = kind, value = v, from = pos, to = pos + n, text = t } end
        end
      end
      pos = pos + n
    end
  end
  close('shading'); close('color')
  return squash(table.concat(text)), out
end

-- { [squashed paragraph text] = { {stretches}, ... in document order } }
local function coloured_paragraphs(docxml)
  docxml = docxml:gsub('<w:rPrChange.-</w:rPrChange>', '')       -- tracked old formatting
                 :gsub('<w:txbxContent>.-</w:txbxContent>', '')   -- nested text-box paragraphs
  local found, count = {}, 0
  for para in docxml:gmatch('<w:p[ >].-</w:p>') do
    local key, stretches = paragraph_stretches(para)
    if #stretches > 0 then
      found[key] = found[key] or {}
      table.insert(found[key], stretches)
      count = count + 1
    end
  end
  return found, count
end

-- Pandoc inlines ------------------------------------------------------------

local skip = { Note = true, Math = true, Image = true, RawInline = true }

local function plain(inlines)
  local buf = {}
  local function go(list)
    for _, x in ipairs(list) do
      if x.t == 'Str' or x.t == 'Code' then table.insert(buf, x.text)
      elseif not skip[x.t] and x.content then go(x.content) end
    end
  end
  go(inlines)
  return squash(table.concat(buf))
end

local function len(x)
  local t = plain({x})
  return utf8.len(t) or #t
end

-- Split s after its k-th non-whitespace character.
local function split_str(s, k)
  if k <= 0 then return '', s end
  local seen = 0
  for p, c in utf8.codes(s) do
    local ch = utf8.char(c)
    if not (ch:match('^%s$') or c == 0xA0) then
      seen = seen + 1
      if seen == k then
        local cut = p + #ch
        return s:sub(1, cut - 1), s:sub(cut)
      end
    end
  end
  return s, ''
end

local containers = {
  Emph = true, Strong = true, Underline = true, Strikeout = true, Superscript = true,
  Subscript = true, SmallCaps = true, Span = true, Link = true, Quoted = true, Cite = true,
}

-- Wrap the characters [a, b) of `list` in spans with the given attribute.
local function wrap(list, a, b, key, value)
  local out, run, pos = pandoc.Inlines{}, nil, 0
  local function flush()
    if run then out:insert(pandoc.Span(run, pandoc.Attr('', {}, {{key, value}}))) end
    run = nil
  end
  local function add(x) run = run or pandoc.Inlines{}; run:insert(x) end
  for _, x in ipairs(list) do
    local n = len(x)
    local s, e = pos, pos + n
    if n == 0 then                             -- spaces, notes, ...: inside only if
      if s > a and s < b then add(x)           -- strictly within the stretch
      else flush(); out:insert(x) end
    elseif e <= a or s >= b then
      flush(); out:insert(x)
    elseif s >= a and e <= b then
      add(x)
    elseif x.t == 'Str' then
      local before, rest = split_str(x.text, a - s)
      local mid, after = split_str(rest, math.min(b, e) - math.max(a, s))
      if before ~= '' then flush(); out:insert(pandoc.Str(before)) end
      add(pandoc.Str(mid))
      if after ~= '' then flush(); out:insert(pandoc.Str(after)) end
    elseif containers[x.t] then
      flush()
      x.content = wrap(x.content, math.max(a - s, 0), math.min(b, e) - s, key, value)
      out:insert(x)
    else
      add(x)                                   -- e.g. Code: cannot be split
    end
    pos = e
  end
  flush()
  return out
end

-- Filter --------------------------------------------------------------------

function Pandoc(doc)
  local input = PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if not input or not input:match('%.docx$') then return doc end
  local docxml = unzip(input, 'word/document.xml')
  if not docxml then return doc end
  local found, count = coloured_paragraphs(docxml)
  if count == 0 then return doc end

  local function colourise(el)
    local queue = found[plain(el.content)]
    if not queue or #queue == 0 then return nil end
    local stretches = table.remove(queue, 1)
    count = count - 1
    -- Longest first, so shorter stretches (labels) nest inside longer ones.
    table.sort(stretches, function(p, q) return (p.to - p.from) > (q.to - q.from) end)
    for _, s in ipairs(stretches) do
      el.content = wrap(el.content, s.from, s.to, s.kind, '#' .. s.value)
    end
    return el
  end
  doc = doc:walk { Para = colourise, Plain = colourise, Header = colourise }

  if count > 0 then
    for _, queue in pairs(found) do
      for _, stretches in ipairs(queue) do
        io.stderr:write('[docx-colors] could not place colour/shading on: "'
          .. stretches[1].text:sub(1, 50) .. '" (text differs after conversion)\n')
      end
    end
  end
  return doc
end
