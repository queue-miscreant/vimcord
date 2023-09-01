if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require("vimcord")

let g:vimcord_discord_username = get(g:, "vimcord_discord_username", "")
let g:vimcord_discord_password = get(g:, "vimcord_discord_password", "")

let g:vimcord_visited_link_color = get(g:, "vimcord_visited_link_color", "f4")


hi def link VimcordOGTitle Title
hi def link VimcordOGDescription LineNr
hi def link VimcordAdditional NonText

