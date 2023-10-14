" buffer.vim
"
" Functions relating to appending messages as groups of lines on a buffer, with
" associated "extra" data.
" Functions here are loosely with discord data (such as UIDs)
"
" A "message" buffer contains two variables on it:
"       b:vimcord_messages_to_extra_data, which maps message numbers to extra
"               message contents (i.e., non-Vim message information)
"       b:vimcord_lines_to_messages, which maps line numbers onto message
"               numbers (i.e., index in the messages_to_extra_data)
"
" Both of these are Lists. Both buffer contents and these variables need to be
" maintained in a consistent state.

" Create a text buffer with initial data for interacting with later
" Return the buffer number
function vimcord#buffer#create_buffer()
  let buf = nvim_create_buf(v:false, v:true)

  " set options for new buffer/window
  call nvim_buf_set_var(buf, "vimcord_lines_to_messages", [])
  call nvim_buf_set_var(buf, "vimcord_messages_to_extra_data", [])
  call nvim_buf_set_option(buf, "modifiable", v:false)

  return buf
endfunction

" Return the first line and last lines that match the message id given
" Lines returned are 0-indexed!
function vimcord#buffer#lines_by_message_number(message_number, ...)
  let buf = 0
  if a:0 >= 1
    let buf = a:1
  endif

  let start_line = 1/0
  let end_line = -1

  let lines_to_messages = nvim_buf_get_var(buf, "vimcord_lines_to_messages")

  for i in range(len(lines_to_messages) - 1, 0, -1)
    let this_number = lines_to_messages[i]
    if this_number == a:message_number
      let start_line = min([start_line, i])
      let end_line = max([end_line, i])
    endif
  endfor

  return [start_line, end_line]
endfunction

function vimcord#buffer#append(discord_message, reply, discord_extra, highlighted)
  " BUFFER MODIFIABLE
  setlocal modifiable

  let message_number = len(b:vimcord_messages_to_extra_data)
  call add(b:vimcord_messages_to_extra_data, a:discord_extra)

  let line_number = len(b:vimcord_lines_to_messages)
  let new_line_count = len(a:discord_message)

  let new_lines = map(a:discord_message, { k, v ->
        \ (repeat(" ", k == 0 ? 0 : g:vimcord_shift_width)) . v
        \ })

  call setline(line_number + 1, new_lines)
  call extend(b:vimcord_lines_to_messages, repeat([message_number], new_line_count))

  if len(a:reply) > 0
    call insert(a:reply, [" ╓─", "discordReply"], 0)
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("vimcord.REPLY_NAMESPACE"),
          \ line_number,
          \ 0,
          \ { "virt_lines": [a:reply], "virt_lines_above": v:true }
          \ )
  endif

  if a:highlighted
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("vimcord.HIGHLIGHT_NAMESPACE"),
          \ line_number,
          \ 0,
          \ { "end_col": 1, "hl_group": "VimcordHighlight" }
          \ )
  endif

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE
endfunction

function vimcord#buffer#edit(message_number, discord_message, discord_extra, highlighted)
  let [start_line, end_line] =
        \ vimcord#buffer#lines_by_message_number(a:message_number)
  if start_line > end_line
    " Message not in buffer, fail silently
    return
  endif
  let window = bufwinid(bufnr())
  let message_number = b:vimcord_lines_to_messages[start_line]

  " BUFFER MODIFIABLE
  setlocal modifiable

  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)
  let reply_extmark = nvim_buf_get_extmarks(
        \ 0,
        \ luaeval("vimcord.REPLY_NAMESPACE"),
        \ [start_line, 0],
        \ [end_line + 1, -1],
        \ { "details": 1 }
        \ )
  let highlight_extmark = nvim_buf_get_extmarks(
        \ 0,
        \ luaeval("vimcord.HIGHLIGHT_NAMESPACE"),
        \ [start_line, 0],
        \ [end_line + 1, -1],
        \ { "details": 1 }
        \ )

  " then set the rest of the line to the new contents
  let new_line_count = len(a:discord_message)
  let new_lines = map(a:discord_message, { k, v ->
        \ (repeat(" ", k == 0 ? 0 : g:vimcord_shift_width)) . v
        \ })
  call append(start_line, new_lines)

  " Delete all lines of the original message
  call deletebufline(bufname(), start_line + new_line_count + 1, end_line + new_line_count + 1)

  " --- Compute new hidden data ---------------------------
  let old_count = end_line - start_line + 1

  " set current lines
  let b:vimcord_messages_to_extra_data[message_number] = a:discord_extra
  for i in range(min([new_line_count, old_count]))
    let b:vimcord_lines_to_messages[start_line + i] = message_number
  endfor

  if old_count < new_line_count
    " add new lines
    call extend(
          \ b:vimcord_lines_to_messages,
          \ repeat([message_number], new_line_count - old_count),
          \ start_line
          \ )
  elseif old_count > new_line_count
    " remove old lines
    call remove(
          \ b:vimcord_lines_to_messages,
          \ end_line - (old_count - new_line_count - 1),
          \ end_line
          \ )
  endif
  " --- Done, buffer lines match hidden lines--------------
  " Move reply extmark
  if len(reply_extmark) > 0
    let extmark_content = reply_extmark[0]
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("vimcord.REPLY_NAMESPACE"),
          \ start_line,
          \ 0,
          \ {
          \   "id": extmark_content[0],
          \   "virt_lines_above": v:true,
          \   "virt_lines": extmark_content[3]["virt_lines"]
          \ })
  endif

  " Move, add, or delete highlight extmark
  if a:highlighted
    let extmark_content = { "end_col": 1, "hl_group": "VimcordHighlight" }
    if len(highlight_extmark) > 0
      let extmark_content["id"] = highlight_extmark[0][0]
    endif
    call nvim_buf_set_extmark(
          \ 0,
          \ luaeval("vimcord.HIGHLIGHT_NAMESPACE"),
          \ start_line,
          \ 0,
          \ extmark_content
          \ )
  elseif len(highlight_extmark) > 0
    call nvim_buf_del_extmark(
          \ 0,
          \ luaeval("vimcord.HIGHLIGHT_NAMESPACE"),
          \ highlight_extmark[0][0]
          \ )
  endif

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE

  return line(".", window) ==# (line("$", window) - new_line_count + old_count)
endfunction

function vimcord#buffer#delete(message_number)
  let [start_line, end_line] =
        \ vimcord#buffer#lines_by_message_number(a:message_number)
  if start_line > end_line
    " Message not in buffer, fail silently
    return
  endif

  " BUFFER MODIFIABLE
  setlocal modifiable

  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)
  call nvim_buf_clear_namespace(0, luaeval("vimcord.REPLY_NAMESPACE"), start_line, end_line + 1)
  call nvim_buf_clear_namespace(0, luaeval("vimcord.HIGHLIGHT_NAMESPACE"), start_line, end_line + 1)
  " delete lines after first one of the message
  call deletebufline(bufname(), start_line + 1, end_line + 1)
  " remove old lines
  call remove(b:vimcord_lines_to_messages, start_line, end_line)

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE
endfunction

function vimcord#buffer#add_link_extmarks(message_number, preview_extmarks, visited_links)
  let [start_line, end_line] = vimcord#buffer#lines_by_message_number(a:message_number)

  if end_line < 0
    echohl ErrorMsg
    echom "Could not add link extmarks to message number " .. a:message_number .. "!"
    echohl None
    return -1
  end

  " sometimes on_message and on_message_exit come very close together
  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)

  if len(a:preview_extmarks) > 0
    let virt_lines = map(
          \ a:preview_extmarks,
          \ { _, v -> insert(v, [repeat(" ", g:vimcord_shift_width), "None"], 0) }
          \ )
    call nvim_buf_set_extmark(0,
          \ luaeval("vimcord.LINKS_NAMESPACE"),
          \ end_line,
          \ 0,
          \ { "virt_lines": virt_lines }
          \ )
  endif

  for link in a:visited_links
    call vimcord#link#color_links_in_buffer(link, end_line)
  endfor

  let window = bufwinid(bufnr())
  if window !=# -1 && !vimcord#buffer#is_scrolled({ "window": window })
    normal Gzb0KJ
  end
endfunction

function vimcord#buffer#add_media_content(message_number, media_content)
  let b:vimcord_messages_to_extra_data[a:message_number]["media_content"] = a:media_content
endfunction

" Check whether the message at the current line is the same as the last one in
" the buffer. A dict can be optionally given as a single argument, with the
" following keys:
" 
" "window": The window ID to use, instead of the current window
" "error": Whether to display an error on failure. Defaults to 1
" "total_lines_before": The line to use as the 'last' line instead of line('$')
function vimcord#buffer#is_scrolled(...)
  let show_error = 1
  let window = 0
  let line_number = line(".")
  let last_line = line("$")
  if a:0 >=# 1
    let window = get(a:1, "window", window)
    let show_error = get(a:1, "error", show_error)

    if window !=# 0
      let line_number = line(".", window)
      let last_line = line("$", window)
    endif

    let last_line = get(a:1, "total_lines_before", last_line)
  endif

  if !exists("b:vimcord_lines_to_messages")
    if show_error
      echoerr "Cannot check if scrolled: invalid buffer"
    endif
    return 0
  endif

  if len(b:vimcord_lines_to_messages) < line_number
    return 0
  endif

  let current_message = b:vimcord_lines_to_messages[line_number - 1]
  let last_message = b:vimcord_lines_to_messages[last_line - 1]

  return current_message !=# last_message
endfunction

function vimcord#buffer#scrolled_message()
  return vimcord#buffer#is_scrolled({ "error": 0 }) ? "Scrolled" : ""
endfunction

" Try to scroll the window after adding lines after the line number given by
" total_lines_before.
" If the message under the cursor's current position matches the message on
" that line, then places the buffer at the top of the (new) last message.
" Otherwise, attempts to scroll down single lines until the last line is
" visible, or the cursor is at the top of the screen.
function vimcord#buffer#scroll_cursor(total_lines_before)
  " Scroll cursor if we were at the bottom before adding lines
  if !vimcord#buffer#is_scrolled({ "total_lines_before": a:total_lines_before }) && !&cursorline
    normal Gzb0KJ
    return
  endif

  " Save the window position
  let window_position = winsaveview()
  " until the bottom line is in view
  while line("w$") < line("$")
    " Scroll down one line
    exe "normal \<c-e>"
    " Cursor was at the top of the screen
    if line(".") !=# window_position["lnum"]
      " Reset and return
      call winrestview(window_position)
      break
    endif
  endwhile
endfunction
