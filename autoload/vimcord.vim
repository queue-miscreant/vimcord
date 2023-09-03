function vimcord#add_discord_data(data, count)
  for i in range(a:count)
    call add(b:discord_content, a:data)
  endfor
endfunction

function vimcord#insert_discord_data(data, count, start_line, end_line)
  let old_count = a:end_line - a:start_line + 1

  " set current lines
  for i in range(min([a:count, old_count]))
    let b:discord_content[a:start_line - 1 + i] = a:data
  endfor

  if old_count < a:count
    " add new lines
    for i in range(a:count - old_count)
      call insert(b:discord_content, a:data, a:start_line - 1)
    endfor
  elseif old_count > a:count
    " remove old lines
    call remove(b:discord_content, a:start_line - 1 + (old_count - a:count), a:end_line)
  endif
endfunction

function vimcord#delete_discord_data(start_line, end_line)
  " remove old lines
  call remove(b:discord_content, a:start_line - 1, a:end_line - 1)
endfunction

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
