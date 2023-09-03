setlocal conceallevel=2
setlocal concealcursor=nv
setlocal nonumber

setlocal wrap
setlocal linebreak
setlocal breakindent
setlocal breakindentopt=shift:4

" TODO: additional data (from opengraph) as extmarks
function s:set_youtube_extmark()
  let current = b:selection[line(".") - 1]
  if exists("current.video_id")
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("neovimpv.DISPLAY_NAMESPACE"),
          \ line(".") - 1,
          \ 0,
          \ { "id": 1,
          \   "virt_text": [[current["length"], "MpvYoutubeLength"]],
          \   "virt_text_pos": "eol",
          \   "virt_lines": [
          \     [[current["channel_name"], "MpvYoutubeChannelName"]],
          \     [[current["views"], "MpvYoutubeViews"]]
          \   ]
          \ })
  elseif exists("current.playlist_id")
    let video_extmarks =
          \ [[[current["channel_name"], "MpvYoutubeChannelName"]]]
    for video in current["videos"]
      call add(video_extmarks, [
            \ ["  ", "MpvDefault"],
            \ [video["title"], "MpvYoutubePlaylistVideo"],
            \ [" ", "MpvDefault"],
            \ [video["length"], "MpvYoutubeLength"]
            \ ])
    endfor
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("neovimpv.DISPLAY_NAMESPACE"),
          \ line(".") - 1,
          \ 0,
          \ { "id": 1,
          \   "virt_text": [[current["video_count"] . " videos", "MpvYoutubeVideoCount"]],
          \   "virt_text_pos": "eol",
          \   "virt_lines": video_extmarks
          \ })
  endif
endfunction

function s:strip_colors(event)
  let new_reg = map(
        \ a:event["regcontents"],
        \ { _, x -> substitute(
          \ x,
          \ "\x1b.. {\\([^{}]\\+\\)} \x1b",
          \ "\\1",
          \ "" )
        \ } )
  call setreg(a:event["regname"], new_reg)
endfunction

augroup discord_messages
  autocmd!
  autocmd TextYankPost <buffer> call s:strip_colors(v:event)
augroup end

if !exists("b:discord_content")
  finish
endif

nmap <silent><buffer> i :<c-u>.call vimcord#action#open_reply(0)<cr>
nmap <silent><buffer> I :<c-u>.call vimcord#action#open_reply(1)<cr>

nmap <silent><buffer> x :<c-u>.call vimcord#action#delete()<cr>
nmap <silent><buffer> X :<c-u>.call vimcord#action#delete()<cr>
nmap <silent><buffer> D :<c-u>.call vimcord#action#delete()<cr>

nmap <silent><buffer> r :<c-u>.call vimcord#action#edit()<cr>
nmap <silent><buffer> R :<c-u>.call vimcord#action#edit()<cr>

nmap <silent><buffer> gx :<c-u>call vimcord#link#open_under_cursor()<cr>
nmap <silent><buffer> <c-g> :<c-u>call vimcord#link#open_most_recent()<cr>

nmap <silent><buffer> A :<c-u>call vimcord#action#write_channel()<cr>
