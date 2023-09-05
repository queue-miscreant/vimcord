if exists("b:current_syntax")
  finish
endif

" Separators
syn region discordChannel start="^ ---" end="$"

hi def link discordNone None
hi def link discordChannel LineNr
hi def link discordReply LineNr

" Code shamelessly taken from AnsiEscPlugin
function s:to_hex(color_number)
" constant colors
  if a:color_number < 16
    let code2rgb = [
          \ "black",
          \ "red3",
          \ "green3",
          \ "yellow3",
          \ "blue3",
          \ "magenta3",
          \ "cyan3",
          \ "gray70",
          \ "gray40",
          \ "red",
          \ "green",
          \ "yellow",
          \ "royalblue3",
          \ "magenta",
          \ "cyan",
          \ "white"
          \ ]
    return code2rgb[a:color_number]
" grayscale
  elseif a:color_number >= 232
    let gray     = a:color_number - 232
    let gray     = 10*gray + 8
    return printf("#%02x%02x%02x", gray, gray, gray)
" others
  else
    let color     = a:color_number - 16
    let code2rgb  = [43, 85, 128, 170, 213, 255]
    let r         = code2rgb[color / 36]
    let g         = code2rgb[(color % 36) / 6]
    let b         = code2rgb[color % 6]
    return printf("#%02x%02x%02x", r, g, b)
  endif
endfunction

syn region discordColorDefault matchgroup=None
      \  start="\%x1B " end=" \%x1B" concealends
syn region discordColorDefault matchgroup=None
      \  start="\%x1B100 " end=" \%x1B" concealends
hi def link discordColorDefault None

" Dynamic color escapes based on (for example) post contents
for i in range(256)
  exe "syn region discordColor" . i . " matchgroup=None"
        \ . " start=\"\\%x1B" . printf("%02x", i) . " \" end=\" \\%x1B\""
        \ . " concealends"
  exe "hi default discordColor" . i . " guifg=" . s:to_hex(i) . " ctermfg=" . i
endfor

" Extra
syn region discordVisitedLink matchgroup=None
      \  start="\%x1BVL " end=" \%x1B" concealends
hi def link discordVisitedLink discordColor244
