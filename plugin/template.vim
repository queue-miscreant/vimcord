if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require("vimcord")

let g:vimcord_discord_username = get(g:, "vimcord_discord_username", "")
let g:vimcord_discord_password = get(g:, "vimcord_discord_password", "")

" let g:vimcord_visited_link_color = get(g:, "vimcord_visited_link_color", "f4")
"
" g:VIMCORD_IMAGE_LINK_FORMATS = []
" g:VIMCORD_VIDEO_LINK_FORMATS = ["youtube.com/watch", "youtube.com/shorts", "youtu.be/"]
" g
" g:VIMCORD_IMAGE_MIMES = ["image/png", "image/jpeg"]
" g:VIMCORD_VIDEO_MIMES = ["image/gif", "video/.*"]

hi def link VimcordOGDefault LineNr
hi def link VimcordOGTitle Title
hi def link VimcordOGDescription VimcordOGDefault
hi def link VimcordAdditional NonText
