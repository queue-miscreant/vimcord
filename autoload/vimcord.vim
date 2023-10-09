function vimcord#close_all()
  let buffer = g:vimcord["discord_message_buffer"]
  let windows = win_findbuf(buffer)
  for window in windows
    call nvim_win_close(window, v:true)
  endfor
endfunction
