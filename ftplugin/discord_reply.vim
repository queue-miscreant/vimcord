setlocal nonumber
setlocal winfixheight

if !(exists("b:vimcord_target_buffer"))
  finish
endif

nmap <silent><buffer> <enter> :call vimcord#push_buffer_contents()<cr>
imap <silent><buffer> <enter> <esc>:call vimcord#push_buffer_contents()<cr>

exe "imap <silent><buffer> <plug>(vimcord_forget_buffer) <esc>:call " 
      \ .. expand("<SID>") .. "forget_buffer_contents()<cr>"
imap <silent><buffer> <c-c> <plug>(vimcord_forget_buffer)

function s:forget_buffer_contents()
  let target_buffer = b:vimcord_target_buffer
  try
    let target_data = nvim_buf_get_var(target_buffer, "vimcord_reply_target_data")
  catch
    return
  endtry

  call vimcord#forget_buffer_contents(target_buffer, target_data)
endfunction

function s:reopen_reply_buffer(reply_buffer)
  let reply_buf = nvim_buf_get_var(a:reply_buffer, "vimcord_reply_buffer")
  exe "below sbuffer " .. reply_buf
  resize 2
endfunction

function s:window_return()
  let target_buffer = b:vimcord_target_buffer
  if exists("b:vimcord_entering_buffer")
    unlet b:vimcord_entering_buffer
    return
  endif
  execute bufwinnr(target_buffer) .. "wincmd w"
endfunction

autocmd WinLeave <buffer> call s:forget_buffer_contents()
autocmd WinClosed <buffer> call timer_start(0, { -> s:reopen_reply_buffer(str2nr(expand("<abuf>"))) })
autocmd WinEnter <buffer> call timer_start(0, { -> s:window_return() })
