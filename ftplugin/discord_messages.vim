setlocal conceallevel=2
setlocal concealcursor=nvc
setlocal nonumber

setlocal wrap
setlocal linebreak
setlocal breakindent

" Remove escape characters used for coloring member names
function s:strip_colors(event)
  let new_reg = map(
        \ a:event["regcontents"],
        \ { _, x -> substitute(
          \ x,
          \ "\\M\\%x1b\\S\\{2,3\\} \\(\\[^\\x1b]\\+\\) \\%x1b",
          \ "\\1",
          \ "" )
        \ } )
  call setreg(a:event["regname"], new_reg)
endfunction

" Close both the reply window and the main window
function s:close_reply_window()
  let buf = g:vimcord["reply_buffer"]
  if winnr("$") == 2
    exe buf .. "bdelete!"
    quitall
  endif

  let win = bufwinnr(buf)
  if win >= 0
    exe win .. "wincmd q"
  endif
endfunction

function s:refresh_connection(...)
  try
    call VimcordInvokeDiscordAction("get_connection_state")
  catch
    " Errors should only happen when the plugin no longer exists
    echohl ErrorMsg
    echom "Could not retrieve connection state! Stopping timer..."
    echohl None

    call s:stop_connection_timer()
  endtry
endfunction

function s:discord_messages_winenter()
  setlocal nocursorline
  if !exists("b:vimcord_connection_timer")
    let b:vimcord_connection_timer = timer_start(
          \ g:vimcord_connection_refresh_interval_seconds,
          \ "s:refresh_connection",
          \ {'repeat': -1})
  endif
endfunction

function s:stop_connection_timer()
  let connection_timer = get(b:, "vimcord_connection_timer", -1)
  if connection_timer >= 0
    call timer_stop(connection_timer)
  endif
endfunction

augroup discord_messages
  autocmd!
  autocmd TextYankPost <buffer> call s:strip_colors(v:event)
  autocmd WinClosed <buffer> call s:close_reply_window()
  autocmd WinEnter <buffer> call s:discord_messages_winenter()
  autocmd WinLeave <buffer> call s:stop_connection_timer()
augroup end

if !(exists("b:vimcord_lines_to_messages") && exists("b:vimcord_messages_to_extra_data"))
  finish
endif

function! s:scroll_message(direction)
  let message_number = b:vimcord_lines_to_messages[line(".") - 1]
  let last_line = -1
  while 1
    let new_message_number = get(b:vimcord_lines_to_messages, line(".") - 1, -1)
    if new_message_number !=# message_number || line(".") ==# last_line
      break
    endif
    let last_line = line(".")
    exe "normal " .. a:direction
  endwhile
endfunction

" Plugin keys
nnoremap <silent><buffer> <Plug>(vimcord_open_reply)
      \ :<c-u>.call vimcord#discord#action#open_reply(0)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_direct_reply)
      \ :<c-u>.call vimcord#discord#action#open_reply(1)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_delete_message)
      \ :<c-u>.call vimcord#discord#action#delete()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_enter_channel)
      \ :<c-u>call vimcord#discord#action#open_channel()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_edit)
      \ :<c-u>.call vimcord#discord#action#edit_start()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_goto_reference)
      \ :<c-u>.call vimcord#discord#local#goto_reference()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_under_cursor)
      \ :<c-u>call vimcord#link#open_under_cursor(0)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_last_link)
      \ :<c-u>call vimcord#link#open_most_recent(0)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_media_under_cursor)
      \ :<c-u>call vimcord#link#open_under_cursor(1)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_last_media)
      \ :<c-u>call vimcord#link#open_most_recent(1)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_message_above)
      \ :<c-u>call <SID>scroll_message("k")<cr>

nnoremap <silent><buffer> <Plug>(vimcord_message_below)
      \ :<c-u>call <SID>scroll_message("j")<cr>

" Actual keymaps
nmap <buffer> i <Plug>(vimcord_open_reply)
nmap <buffer> I <Plug>(vimcord_open_direct_reply)

nmap <buffer> X <Plug>(vimcord_delete_message)
nmap <buffer> D <Plug>(vimcord_delete_message)

nmap <buffer> A <Plug>(vimcord_enter_channel)
nmap <buffer> <c-t> <Plug>(vimcord_enter_channel)

nmap <buffer> r <Plug>(vimcord_edit)
nmap <buffer> R <Plug>(vimcord_edit)

nmap <buffer> K <Plug>(vimcord_message_above)
nmap <buffer> J <Plug>(vimcord_message_below)

nmap <buffer> gx <Plug>(vimcord_open_under_cursor)
nmap <buffer> <c-g> <Plug>(vimcord_open_last_link)

nmap <buffer> <a-g> <Plug>(vimcord_open_last_media)

nmap <buffer> <enter> <Plug>(vimcord_goto_reference)
