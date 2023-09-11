function vimcord#buffer#add_extra_data(discord_channels_dict, discord_members_dict, user_id)
  let g:vimcord["channel_names"] = a:discord_channels_dict
  let g:vimcord["server_members"] = a:discord_members_dict
  let g:vimcord["discord_user_id"] = a:user_id
endfunction

" Return the first line and last lines that match the message id given
" Lines returned are 0-indexed!
function vimcord#buffer#lines_by_message_id(message_id, ...)
  let buf = 0
  if a:0 >= 1
    let buf = a:1
  endif

  let start_line = 1/0
  let end_line = -1
  let i = 0
  for data in nvim_buf_get_var(buf, "discord_content")
    if exists("data.message_id") && data["message_id"] == a:message_id
      let start_line = min([start_line, i])
      let end_line = max([end_line, i])
    endif
    let i += 1
  endfor

  return [start_line, end_line]
endfunction

function vimcord#buffer#append(indent_width, discord_message, reply, discord_extra, add_spaces)
  " BUFFER MODIFIABLE
  setlocal modifiable

  let line_number = len(b:discord_content)
  let new_line_count = len(a:discord_message)

  let new_lines = map(a:discord_message, { k, v ->
        \ (repeat(" ", k == 0 ? a:add_spaces : (a:indent_width - 1))) . v
        \ })

  call setline(line_number + 1, new_lines)
  for i in range(new_line_count)
    call add(b:discord_content, a:discord_extra)
  endfor

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
    if !exists("b:discord_content[row]")
      " extmark still around, but not at an available line
      call nvim_buf_del_extmark(0, luaeval("vimcord.REPLY_NAMESPACE"), id)
    elseif b:discord_content[row]["reply_message_id"] == a:reply_id
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
  endfor
endfunction

function vimcord#buffer#edit(indent_width, discord_message, as_reply, discord_extra)
  let [start_line, end_line] =
        \ vimcord#buffer#lines_by_message_id(a:discord_extra["message_id"])
  if start_line > end_line
    " Message not in buffer, fail silently
    return
  endif

  " BUFFER MODIFIABLE
  setlocal modifiable

  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), start_line, end_line + 1)
  if start_line + 1 <= end_line
    call deletebufline(bufname(), start_line + 1, end_line)
  end

  " then set the rest of the line to the new contents
  let new_line_count = len(a:discord_message)
  let new_lines = map(a:discord_message, { k, v ->
        \ (repeat(" ", k == 0 ? 1 : (a:indent_width - 1))) . v
        \ })
  call setline(start_line + 1, new_lines)

  " --- Compute new hidden data ---------------------------
  let old_count = end_line - start_line + 1

  " set current lines
  for i in range(min([new_line_count, old_count]))
    let b:discord_content[start_line + i] = a:discord_extra
  endfor

  if old_count < new_line_count
    " add new lines
    for i in range(new_line_count - old_count)
      call insert(b:discord_content, a:discord_extra, start_line)
    endfor
  elseif old_count > new_line_count
    " remove old lines
    call remove(b:discord_content, start_line + (old_count - new_line_count), end_line)
  endif
  " --- Done, buffer lines match hidden lines--------------
  call s:redo_reply_extmarks(a:discord_extra["message_id"], a:as_reply)

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE

  return line(".") == (line("$") - new_line_count + old_count)
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
  call remove(b:discord_content, start_line, end_line)

  call s:redo_reply_extmarks(a:message_id, [[" ╓─(Deleted)", "discordReply"]])

  setlocal nomodifiable
  " BUFFER NOT MODIFIABLE
endfunction

function vimcord#buffer#add_link_extmarks(message_id, extmarks)
  let [start_line, end_line] = vimcord#buffer#lines_by_message_id(a:message_id)
  let window = bufwinid(bufnr())

  if end_line + 1 > line("$", window)
    echoerr "Could not add links to message id " .. a:message_id .. "!"
    return -1
  end

  " sometimes on_message and on_message_exit come very close together
  call nvim_buf_clear_namespace(0, luaeval("vimcord.LINKS_NAMESPACE"), end_line, end_line + 1)

  let bufindentopt = nvim_win_get_option(window, "breakindentopt")
  try
    let split_width = str2nr(
          \ split(split(bufindentopt, "shift:", 1)[1], ",")[0]
          \ )
  catch
    let split_width = 0
  endtry

  let virt_lines = map(
        \ a:extmarks,
        \ { _, v -> insert(v, [repeat(" ", split_width), "None"], 0) }
        \ )
  call nvim_buf_set_extmark(0,
        \ luaeval("vimcord.LINKS_NAMESPACE"),
        \ end_line,
        \ 0,
        \ { "virt_lines": virt_lines }
        \ )

  if line(".") == line("$")
    normal zb
  end
  return end_line
endfunction

function vimcord#buffer#add_media_content(line_number, media_content)
  let b:discord_content[a:line_number]["media_content"] = a:media_content
endfunction

function vimcord#buffer#goto_reference() range
  if len(b:discord_content) <= a:firstline - 1
    echoerr "No message under cursor"
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]
  try
    let reply_id = message_data["reply_message_id"]
    if reply_id ==# v:null
      echoerr "Message has no reply"
      return
    endif
  catch
    echoerr "Message has no reply"
    return
  endtry

  let [start_line, end_line] = vimcord#buffer#lines_by_message_id(reply_id)
  if end_line == -1
    " TODO: try to prepend reference contents
    echoerr "Replied message not in buffer!"
    return
  endif

  call cursor(start_line + 1, 0)
endfunction
