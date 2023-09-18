if !has("nvim")
  echo "Plugin not supported outside of nvim"
  finish
endif

lua require("vimcord")

let g:vimcord_discord_username = get(g:, "vimcord_discord_username", "")
let g:vimcord_discord_password = get(g:, "vimcord_discord_password", "")

let g:vimcord_dnd_paste_threshold = get(g:, "vimcord_dnd_paste_threshold", 8)
let g:vimcord_shift_width = max([get(g:, "vimcord_shift_width", 4), 1])
let g:vimcord_show_link_previews = get(g:, "vimcord_show_link_previews", 1)
let g:vimcord_max_suggested_servers = get(g:, "vimcord_max_suggested_servers", 10)

" Link open settings
let g:vimcord_image_opener = get(g:, "vimcord_image_opener", "feh")
let g:vimcord_video_opener = get(g:, "vimcord_video_opener", "mpv")

let g:vimcord_image_link_formats = get(g:, "vimcord_image_link_formats", [])
let g:vimcord_video_link_formats = get(g:, "vimcord_video_link_formats", [
      \ "youtube.com/watch",
      \ "youtube.com/shorts",
      \ "youtu.be/",
      \ "tiktok.com/t/"
      \ ])
let g:vimcord_image_mimes = get(g:, "vimcord_image_mimes", ["image/png", "image/jpeg"])
let g:vimcord_video_mimes = get(g:, "vimcord_video_mimes", ["image/gif", "video/.*"])

hi def link VimcordOGDefault LineNr
hi def link VimcordOGSiteName VimcordOGDefault
hi def link VimcordOGTitle Title
hi def link VimcordOGDescription Conceal
hi def link VimcordAdditional NonText

hi def VimcordHighlight cterm=reverse gui=reverse
hi def VimcordVisitedLink ctermfg=244 guifg=#888888

" Dictionary used for runtime data
let g:vimcord = {}


" Airline support
" XXX: Investigate other status line plugins
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

let g:airline_filetype_overrides["discord_messages"] = get(
      \ g:airline_filetype_overrides,
      \ "discord_messages",
      \ ["Discord", "%{VimcordShowScrolled()}"]
      \ )
let g:airline_filetype_overrides["discord_reply"] = get(
      \ g:airline_filetype_overrides,
      \ "discord_reply",
      \ ["Message", "%{VimcordShowChannel()}"]
      \ )

function! VimcordLogin()
  try
    let g:vimcord_discord_username = input("Discord username: ")
    let g:vimcord_discord_password = inputsecret("Discord password: ")
  catch
    " Ctrl-c given
    try
      unlet g:vimcord_discord_username
      unlet g:vimcord_discord_password
    catch
    endtry

    echohl ErrorMsg
    echo "Cancelled login"
    echohl None

    return
  endtry

  if g:vimcord_discord_username ==# "" || g:vimcord_discord_password ==# ""
    unlet g:vimcord_discord_username
    unlet g:vimcord_discord_password

    echohl ErrorMsg
    echo "Empty credentials given. Aborting login."
    echohl None

    return
  endif

  Discord!

  unlet g:vimcord_discord_username
  unlet g:vimcord_discord_password
endfunction

command! -nargs=0 DiscordLogin call timer_start(0, { -> VimcordLogin() })
