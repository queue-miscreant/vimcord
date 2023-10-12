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
let g:vimcord_connection_refresh_interval_seconds = get(
      \ g:,
      \ "vimcord_connection_refresh_interval_seconds",
      \ 60)


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

hi def VimcordHighlight ctermbg=darkyellow guibg=#FFFF00 ctermfg=yellow guifg=#88FF44
hi def VimcordVisitedLink ctermfg=244 guifg=#888888

" Dictionary used for runtime data
let g:vimcord = {}

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

" Airline support
" XXX: Investigate other status line plugins
function! VimcordShowConnection()
  let ready = get(g:vimcord, "discord_ready", -1)
  let not_connected = get(g:vimcord, "discord_not_connected", -1)
  let logged_in = get(g:vimcord, "discord_logged_in", -1)
  if ready <= 0
    return "Not connected to daemon!"
  elseif logged_in <= 0
    return "Not logged in!"
  elseif not_connected > 0
    return "Disconnected!"
  endif
  return ""
endfunction

function! VimcordAirline(...)
  if &filetype == "discord_messages"
    let w:airline_section_a = airline#section#create_left(["vimcord_scrolled"])
    let w:airline_section_b = ""
    let w:airline_section_c = "Discord"

    let w:airline_section_x = ""
    let w:airline_section_y = ""
    let w:airline_section_z = airline#section#create_right(["vimcord_connection"])
  elseif &filetype == "discord_reply"
    let w:airline_section_a = airline#section#create_left(["vimcord_action"])
    let w:airline_section_b = ""
    let w:airline_section_c = airline#section#create_left(["vimcord_channel"])

    let w:airline_section_x = ""
    let w:airline_section_y = ""
    let w:airline_section_z = ""
  endif
endfunction

try
  call airline#add_statusline_func('VimcordAirline')
  call airline#add_inactive_statusline_func('VimcordAirline')
  call airline#parts#define_function('vimcord_scrolled', "vimcord#buffer#scrolled_message")
  call airline#parts#define_function('vimcord_connection', "VimcordShowConnection")
  call airline#parts#define_function('vimcord_action', "vimcord#discord#action#show_reply_action")
  call airline#parts#define_function('vimcord_channel', "vimcord#discord#action#show_reply_channel")
catch
endtry
