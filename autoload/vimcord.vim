function vimcord#scroll_cursor(lines_added)
  " Scroll cursor if we were at the bottom before adding lines
  if getpos(".")[1:2] == [line("$") - a:lines_added, 1]
    normal Gzb0
    return
  endif

  " until we're scrolled upward
  while line("w$") !=# line("$")
    " Save the window position
    let window_position = winsaveview()
    " Scroll down one line
    exe "normal \<c-e>"
    " Cursor was at the top of the screen
    if line(".") !=# window_position["lnum"]
      " Reset and return
      call winrestview(window_position)
      return
    endif
  endwhile

  call timer_start(0, { -> execute("redraw") })
endfunction


function vimcord#close_all(buffer)
  let windows = win_findbuf(a:buffer)
  for window in windows
    call nvim_win_close(window, v:true)
  endfor
endfunction
