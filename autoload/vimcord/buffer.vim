function vimcord#buffer#add_extra_data(discord_channels_dict, discord_members_dict, user_id)
  let g:vimcord["channel_names"] = a:discord_channels_dict
  let g:vimcord["server_members"] = a:discord_members_dict
  let g:vimcord["discord_user_id"] = a:user_id
endfunction

" Return the first line and last lines that match the message id given
" Lines returned are 0-indexed!
" TODO: this should be message NUMBER not id
"       we can identify the id first, then find the line...
function vimcord#buffer#lines_by_message_id(message_id, ...)
  let buf = 0
  if a:0 >= 1
    let buf = a:1
  endif

  let start_line = 1/0
  let end_line = -1

  let lines_to_messages = nvim_buf_get_var(buf, "vimcord_lines_to_messages")
  let messages_to_extra = nvim_buf_get_var(buf, "vimcord_messages_to_extra_data")

  for i in range(len(lines_to_messages) - 1, 0, -1)
    let message_number = lines_to_messages[i]
    let message_data = messages_to_extra[message_number]
    if exists("message_data.message_id") && message_data["message_id"] == a:message_id
      let start_line = min([start_line, i])
      let end_line = max([end_line, i])
    endif
  endfor

  return [start_line, end_line]
endfunction

function vimcord#buffer#append(discord_message, reply, discord_extra)
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

  echom line_number new_line_count line("$", bufwinid(bufnr()))

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

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE
endfunction

" TODO: improve this. use fewer message_id and more message_numbers
"       alternatively, separate discord and general messaging more
function s:redo_reply_extmarks(reply_id, new_contents)
  call insert(a:new_contents, [" ╓─", "discordReply"], 0)

  let reply_extmarks = nvim_buf_get_extmarks(
        \ 0,
        \ luaeval("vimcord.REPLY_NAMESPACE"),
        \ 0,
        \ -1,
        \ {}
        \ )

  for [id, row, column] in reply_extmarks
    if !exists("b:vimcord_lines_to_messages[row]")
      " extmark still around, but not at an available line
      call nvim_buf_del_extmark(0, luaeval("vimcord.REPLY_NAMESPACE"), id)
    else
      let message_number = b:vimcord_lines_to_messages[row]
      if b:vimcord_messages_to_extra_data[message_number]["reply_message_id"] == a:reply_id
        call nvim_buf_set_extmark(
              \ 0,
              \ luaeval("vimcord.REPLY_NAMESPACE"),
              \ row,
              \ column,
              \ {
              \   "id": id,
              \   "virt_lines": [a:new_contents],
              \   "virt_lines_above": v:true
              \ })
      endif
    endif
  endfor
endfunction

function vimcord#buffer#edit(discord_message, as_reply, discord_extra)
  " TODO: message number instead
  let [start_line, end_line] =
        \ vimcord#buffer#lines_by_message_id(a:discord_extra["message_id"])
  if start_line > end_line
    " Message not in buffer, fail silently
    return
  endif
  let window = bufwinid(bufnr())
  let message_number = b:vimcord_lines_to_messages[start_line]

  " BUFFER MODIFIABLE
  setlocal modifiable

  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)
  call nvim_buf_clear_namespace(0, luaeval("vimcord.REPLY_NAMESPACE"), start_line, end_line + 1)

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
  call nvim_buf_set_extmark(
        \ 0,
        \ luaeval("vimcord.REPLY_NAMESPACE"),
        \ start_line,
        \ 0,
        \ { "virt_lines": [a:reply], "virt_lines_above": v:true }
        \ )
  call s:redo_reply_extmarks(a:discord_extra["message_id"], a:as_reply)

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE

  return line(".", window) ==# (line("$", window) - new_line_count + old_count)
endfunction

function vimcord#buffer#delete(message_id)
  let [start_line, end_line] =
        \ vimcord#buffer#lines_by_message_id(a:message_id)
  if start_line > end_line
    " Message not in buffer, fail silently
    return
  endif

  " BUFFER MODIFIABLE
  setlocal modifiable

  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)
  " delete lines after first one of the message
  call deletebufline(bufname(), start_line + 1, end_line + 1)
  " remove old lines
  call remove(b:vimcord_lines_to_messages, start_line, end_line)

  call s:redo_reply_extmarks(a:message_id, [[" ╓─(Deleted)", "discordReply"]])

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE
endfunction

function vimcord#buffer#add_link_extmarks(message_id, extmarks)
  let [start_line, end_line] = vimcord#buffer#lines_by_message_id(a:message_id)
  let window = bufwinid(bufnr())

  if end_line + 1 > line("$", window)
    echohl ErrorMsg
    echom "Could not add links to message id " .. a:message_id .. "!"
    echohl None
    return -1
  end

  " sometimes on_message and on_message_exit come very close together
  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), end_line, end_line + 1)

  let virt_lines = map(
        \ a:extmarks,
        \ { _, v -> insert(v, [repeat(" ", g:vimcord_shift_width), "None"], 0) }
        \ )
  call nvim_buf_set_extmark(0,
        \ luaeval("vimcord.LINKS_NAMESPACE"),
        \ end_line,
        \ 0,
        \ { "virt_lines": virt_lines }
        \ )

  if line(".", window) == line("$", window)
    normal zb
  end
  return end_line
endfunction

function vimcord#buffer#add_media_content(line_number, media_content)
  let message_number = b:vimcord_lines_to_messages[a:line_number - 1]
  let b:vimcord_messages_to_extra_data[message_number]["media_content"] = a:media_content
endfunction

function vimcord#buffer#goto_reference() range
  if len(b:vimcord_lines_to_messages) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_number = b:vimcord_lines_to_messages[a:line_number - 1]
  let message_data = b:vimcord_messages_to_extra_data[message_number]
  try
    let reply_id = message_data["reply_message_id"]
    if reply_id ==# v:null
      echohl ErrorMsg
      echo "Message has no reply"
      echohl None
      return
    endif
  catch
    echohl ErrorMsg
    echo "Message has no reply"
    echohl None
    return
  endtry

  let [start_line, end_line] = vimcord#buffer#lines_by_message_id(reply_id)
  if end_line == -1
    " TODO: try to prepend reference contents
    echohl ErrorMsg
    echo "Replied message not in buffer!"
    echohl None
    return
  endif

  call cursor(start_line + 1, 0)
endfunction
