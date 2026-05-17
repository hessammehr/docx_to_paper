-- readable-citekeys.lua
--
-- For Pandoc's docx+citations reader: rewrite Zotero's numeric item ids
-- to stable, human-readable citekeys.
--
-- Preference order:
--   1. existing Zotero/Better BibTeX citation-key, if present
--   2. FirstAuthorYear, e.g. Kemppinen2020
-- Duplicate keys get suffixes: Smith2020a, Smith2020b, ...

local stringify = pandoc.utils.stringify

local function clean_key(s)
  s = (s or ''):gsub('%s+', ''):gsub('[^A-Za-z0-9:_-]', '')
  if s == '' then return 'ref' end
  return s
end

local function first_author_family(ref)
  local authors = ref.author
  if type(authors) == 'table' and #authors > 0 then
    local a = authors[1]
    if type(a) == 'table' then
      return stringify(a.family or a.literal or 'Anon')
    end
  end
  return 'Anon'
end

local function year(ref)
  local issued = stringify(ref.issued or '')
  return issued:match('%d%d%d%d') or 'nd'
end

local function base_key(ref)
  local existing = stringify(ref['citation-key'] or '')
  if existing ~= '' then return clean_key(existing) end
  return clean_key(first_author_family(ref) .. year(ref))
end

function Pandoc(doc)
  local refs = doc.meta.references
  if not refs then return doc end

  local counts = {}
  for _, ref in ipairs(refs) do
    local old = stringify(ref.id or '')
    if old ~= '' then
      local base = base_key(ref)
      counts[base] = (counts[base] or 0) + 1
    end
  end

  local seen = {}
  local keymap = {}
  for _, ref in ipairs(refs) do
    local old = stringify(ref.id or '')
    if old ~= '' then
      local base = base_key(ref)
      local key = base
      if counts[base] > 1 then
        local n = seen[base] or 0
        seen[base] = n + 1
        key = base .. string.char(string.byte('a') + n)
      end
      keymap[old] = key
      ref.id = key
      ref['citation-key'] = key
    end
  end

  doc.blocks = doc.blocks:walk {
    Cite = function(el)
      for _, cit in ipairs(el.citations) do
        if keymap[cit.id] then
          cit.id = keymap[cit.id]
        end
      end
      return el
    end
  }

  return doc
end
