setlocal nonumber
setlocal wrap
setlocal linebreak
setlocal breakindent

" Plugin maps
nmap <silent><buffer> <plug>(vimcord_push_contents) :call vimcord#reply#push_buffer_contents()<cr>
nmap <silent><buffer> <plug>(vimcord_forget_buffer) :call vimcord#reply#forget_reply_contents()<cr>

" Real maps
nmap <silent><buffer> <enter> <plug>(vimcord_push_contents)
imap <silent><buffer> <enter> <esc><plug>(vimcord_push_contents)

nmap <silent><buffer> <c-c> <plug>(vimcord_forget_buffer)
imap <silent><buffer> <c-c> <esc><plug>(vimcord_forget_buffer)
nmap <silent><buffer> <esc> <plug>(vimcord_forget_buffer)

imap <buffer><silent> <tab> <c-r>= pumvisible() ? "\<lt>c-n>" : "\<lt>tab>"<cr>
imap <buffer><silent> <s-tab> <c-r>= pumvisible() ? "\<lt>c-p>" : "\<lt>s-tab>"<cr>

" Autocmds
function s:window_return()
  if exists("b:vimcord_entering_buffer")
    unlet b:vimcord_entering_buffer
    return
  endif
  wincmd p
endfunction

augroup discord_reply
  autocmd!
  autocmd WinLeave <buffer> call vimcord#reply#forget_reply_contents()
  autocmd WinClosed <buffer> call timer_start(0, { -> vimcord#reply#create_reply_window(1) })
  autocmd WinEnter <buffer> call timer_start(0, { -> s:window_return() })
augroup end
