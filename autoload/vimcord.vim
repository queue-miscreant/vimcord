function vimcord#scroll_cursor(lines_added)
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

  " Scroll cursor if we were at the bottom before adding lines
  if line(".") == line("$") - a:lines_added
    normal Gzb0
  endif

  redraw
endfunction
