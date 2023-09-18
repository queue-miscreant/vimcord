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

function vimcord#push_buffer_contents()
  let target_data = get(g:vimcord, "reply_target_data", {})

  if len(target_data) ==# 0
    echohl WarningMsg
    echo "No channel targeted"
    echohl None
    return
  endif

  let buffer_contents = join(getbufline(
        \ g:vimcord["reply_buffer"],
        \ 1,
        \ line("$")
        \ ), "\n")

  let filenames = []
  try
    let filenames = nvim_buf_get_var(g:vimcord["reply_buffer"],
          \ "vimcord_uploaded_files")
  catch
  endtry

  let try_handle = vimcord#action#try_handle(target_data["action"])
  if !try_handle
    call VimcordInvokeDiscordAction(
          \ target_data["action"],
          \ target_data["data"],
          \ { "content": buffer_contents, "filenames": filenames }
          \ )
  endif

  call vimcord#forget_reply_contents()
  normal Gzb0
endfunction

function vimcord#forget_reply_contents()
  " Remove the status line
  if exists("g:vimcord.reply_target_data")
    " Easy mode for airline
    unlet g:vimcord["reply_target_data"]

    " Not-so-easy otherwise
    if !exists(":AirlineRefresh")
      for window in win_findbuf(g:vimcord["reply_buffer"])
        call nvim_win_set_option(window, "statusline", "")
      endfor
    endif
  endif

  " Clear the uploaded files
  call nvim_buf_set_var(g:vimcord["reply_buffer"], "vimcord_uploaded_files", [])
  " Restore fuzzy completion data
  try
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_fuzzy_match")
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_fuzzy_match_results")
    call nvim_set_option(
          \ "completeopt",
          \ nvim_buf_get_var(g:vimcord["reply_buffer"], "vimcord_previous_completeopt")
          \ )
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
    call nvim_set_option(
          \ "pumheight",
          \ nvim_buf_get_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
          \ )
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
  catch
  endtry

  wincmd p

  " Delete the reply buffer contents
  call deletebufline(g:vimcord["reply_buffer"], 1, "$")
  echo ""
endfunction

function vimcord#create_reply_window(do_split)
  if exists("g:vimcord.reply_buffer")
    let buffer = g:vimcord["reply_buffer"]
  else
    let buffer = nvim_create_buf(v:false, v:true)
    let g:vimcord["reply_buffer"] = buffer
  endif

  let reply_in_current_tab = len(
        \   filter(
        \     map(win_findbuf(buffer), "win_id2tabwin(v:val)[0]"),
        \     "v:val ==# tabpagenr()"
        \   )
        \ )

  let current_window = winnr()
  if a:do_split && !reply_in_current_tab
    " Go to the bottom window
    let prev_window = current_window
    while 1
      wincmd j
      if prev_window == winnr()
        break
      endif
      prev_window = winnr()
    endwhile

    exe "below sbuffer " .. buffer
    resize 2
    setlocal winfixheight
    setlocal filetype=discord_reply
  endif

  exe current_window .. "wincmd w"
  return bufwinnr(buffer)
endfunction

function vimcord#close_all(buffer)
  let windows = win_findbuf(a:buffer)
  for window in windows
    call nvim_win_close(window, v:true)
  endfor
endfunction
