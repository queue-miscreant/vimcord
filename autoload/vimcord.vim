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

function vimcord#push_buffer_contents()
  let target_buffer = b:vimcord_target_buffer
  try
    let target_data = nvim_buf_get_var(target_buffer, "vimcord_reply_target_data")
  catch
    echohl WarningMsg
    echo "No channel targeted"
    echohl None
    return
  endtry

  let buffer_contents = join(getline(1, line("$")), "\n")
  if trim(buffer_contents) ==# ""
    return
  endif

  call VimcordInvokeDiscordAction(
        \ target_data["action"],
        \ target_data["data"],
        \ buffer_contents
        \ )

  call vimcord#forget_buffer_contents(target_buffer, target_data)
endfunction

function vimcord#forget_buffer_contents(target_buffer, target_data)
  call nvim_buf_set_var(a:target_buffer, "vimcord_reply_target_data", {})
  call nvim_buf_set_var(a:target_buffer, "vimcord_target_channel", v:null)

  "TODO: might not be necessary
  if exists(":AirlineRefresh")
    AirlineRefresh!
  else
    " normal status line here
  endif
  redrawstatus
  %delete _
  echo ""

  exe bufwinnr(a:target_buffer) .. "wincmd w"
  setlocal nocursorline
endfunction
