if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require("vimcord")

let g:vimcord_discord_username = get(g:, "vimcord_discord_username", "")
let g:vimcord_discord_password = get(g:, "vimcord_discord_password", "")
let g:vimcord_dnd_filenames = get(g:, "vimcord_dnd_filenames", 1)
let g:vimcord_dnd_paste_threshold = get(g:, "vimcord_dnd_paste_threshold", 8)

" let g:vimcord_visited_link_color = get(g:, "vimcord_visited_link_color", "f4")
"
" g:VIMCORD_IMAGE_LINK_FORMATS = []
" g:VIMCORD_VIDEO_LINK_FORMATS = ["youtube.com/watch", "youtube.com/shorts", "youtu.be/"]
" g
" g:VIMCORD_IMAGE_MIMES = ["image/png", "image/jpeg"]
" g:VIMCORD_VIDEO_MIMES = ["image/gif", "video/.*"]

hi def link VimcordOGDefault LineNr
hi def link VimcordOGSiteName VimcordOGDefault
hi def link VimcordOGTitle Title
hi def link VimcordOGDescription Conceal
hi def link VimcordAdditional NonText

let g:vimcord = {}

function VimcordShowScrolled()
  let cursor = nvim_win_get_cursor(0)
  let buf = nvim_win_get_buf(0)

  if cursor ==# [nvim_buf_line_count(buf), 0]
    return ""
  endif
  return "Scrolled"
endfunction

function VimcordShowChannel()
  try
    let channel_id = g:vimcord["reply_target_data"]["data"]["channel_id"]
    return g:vimcord["channel_names"][channel_id]
  catch
    return ""
  endtry
endfunction

if !exists("g:airline_filetype_overrides")
  let g:airline_filetype_overrides = {}
endif

" TODO: non-user-invasive
let g:airline_filetype_overrides["discord_messages"] = ["Discord", "%{VimcordShowScrolled()}"]
let g:airline_filetype_overrides["discord_reply"] = ["Message", "%{VimcordShowChannel()}"]
