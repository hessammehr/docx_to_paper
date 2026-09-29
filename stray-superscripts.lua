-- stray-superscripts.lua
--
-- PDF stage only. Drop superscripts that look like citation numbers (e.g. ^10^,
-- ^8,9^, ^4-6^) and report each on stderr. These are flattened or placeholder
-- citations left in the Word document; they carry no reference data and would
-- clash with the numbering produced by citeproc. A superscript counts as a
-- citation only if it starts with a digit and does not follow a number, a
-- single letter or a unit (so x^2^, 10^6^ and cm^-1^ are left alone).
-- Links whose only content is such a superscript are dropped too.

local stringify = pandoc.utils.stringify

local units = {}
for u in ('m cm mm um µm nm pm km s ms us µs ns ps g kg mg ug µg mol mmol L mL uL µL '
       .. 'l ml K Pa kPa MPa Hz kHz MHz GHz W kW J kJ eV keV V mV A mA C Å'):gmatch('%S+') do
  units[u] = true
end

local function is_number_list(inlines)
  local s = stringify(inlines)
  return s:match('^%d[%d,%-–%s]*$') ~= nil
end

local function exponent_base(prev)
  if not prev then return false end
  if prev.t ~= 'Str' then return false end
  local s = prev.text
  if s:match('%d$') then return true end                 -- 10^6^
  local word = s:match('([%a\128-\255]+)$')
  if not word then return false end                      -- ends in punctuation
  if utf8.len(word) == 1 then return true end            -- x^2^
  return units[word] == true                             -- cm^3^
end

local function citation_like(el, prev)
  local sup = el
  if el.t == 'Link' then
    if #el.content ~= 1 or el.content[1].t ~= 'Superscript' then return false end
    sup = el.content[1]
  elseif el.t ~= 'Superscript' then
    return false
  end
  return is_number_list(sup.content) and not exponent_base(prev)
end

function Pandoc(doc)
  local found = {}
  for i, block in ipairs(doc.blocks) do
    doc.blocks[i] = block:walk {
      Inlines = function(inls)
        local out = pandoc.Inlines{}
        for j, el in ipairs(inls) do
          if el.t == 'Link' and #el.content == 0 then
            -- link whose superscript was dropped
          elseif citation_like(el, inls[j - 1]) then
            table.insert(found, stringify(el) .. ' in: ' .. stringify(block):sub(1, 70))
          else
            out:insert(el)
          end
        end
        return out
      end,
    }
  end
  for _, f in ipairs(found) do
    io.stderr:write('[stray-superscripts] dropped ' .. f .. '\n')
  end
  return doc
end
