setlocal conceallevel=2
setlocal concealcursor=nvc
setlocal nonumber

setlocal wrap
setlocal linebreak
setlocal breakindent
setlocal breakindentopt=shift:4

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

augroup discord_messages
  autocmd!
  autocmd TextYankPost <buffer> call s:strip_colors(v:event)
  autocmd WinClosed <buffer> call s:close_reply_window()
  autocmd WinEnter <buffer> setlocal nocursorline
augroup end

if !(exists("b:discord_content"))
  finish
endif

" Plugin keys
nnoremap <silent><buffer> <Plug>(vimcord_open_reply)
      \ :<c-u>.call vimcord#action#new_open_reply(0)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_direct_reply)
      \ :<c-u>.call vimcord#action#new_open_reply(1)<cr>

nnoremap <silent><buffer> <Plug>(vimcord_delete_message)
      \ :<c-u>.call vimcord#action#delete()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_enter_channel)
      \ :<c-u>call vimcord#action#new_write_channel()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_edit)
      \ :<c-u>.call vimcord#action#edit_start()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_goto_reference)
      \ :<c-u>.call vimcord#buffer#goto_reference()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_under_cursor)
      \ :<c-u>call vimcord#link#open_under_cursor()<cr>

nnoremap <silent><buffer> <Plug>(vimcord_open_last_link)
      \ :<c-u>call vimcord#link#open_most_recent()<cr>

" Actual keymaps
nmap <silent><buffer> i <Plug>(vimcord_open_reply)
nmap <silent><buffer> I <Plug>(vimcord_open_direct_reply)

nmap <silent><buffer> X <Plug>(vimcord_delete_message)
nmap <silent><buffer> D <Plug>(vimcord_delete_message)

nmap <silent><buffer> A <Plug>(vimcord_enter_channel)

nmap <silent><buffer> r <Plug>(vimcord_edit)
nmap <silent><buffer> R <Plug>(vimcord_edit)

nmap <silent><buffer> gx <Plug>(vimcord_open_under_cursor)
nmap <silent><buffer> <c-g> <Plug>(vimcord_open_last_link)

nmap <silent><buffer> <enter> <Plug>(vimcord_goto_reference)
