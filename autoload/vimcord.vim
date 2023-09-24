function vimcord#close_all(buffer)
  let windows = win_findbuf(a:buffer)
  for window in windows
    call nvim_win_close(window, v:true)
  endfor
endfunction
