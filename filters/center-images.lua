-- center-images.lua
--
-- PDF stage only. Pandoc's docx reader drops paragraph alignment, so an image
-- sitting alone in a paragraph without a caption ends up flush left. Word
-- centres these by default; do the same in LaTeX output. Figures (captioned
-- images) are left alone.

traverse = 'topdown'

function Figure(el)
  return el, false
end

function Para(el)
  if FORMAT:match('latex') and #el.content == 1 and el.content[1].t == 'Image' then
    return {
      pandoc.RawBlock('latex', '\\begin{center}'),
      pandoc.Plain(el.content),
      pandoc.RawBlock('latex', '\\end{center}'),
    }
  end
end
