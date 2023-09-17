" discord.viM
"
" Functions relating Discord-identifying data, stored in b:vimcord_messages_to_extra_data
" Fields stored here include channel, message, and server IDs
"
" Also provides function for reply extmark manipulation

function vimcord#discord#add_extra_data(discord_channels_dict, discord_members_dict, user_id)
  let g:vimcord["channel_names"] = a:discord_channels_dict
  let g:vimcord["server_members"] = a:discord_members_dict
  let g:vimcord["discord_user_id"] = a:user_id
endfunction


function vimcord#discord#get_message_number(message_id)
  " call nvim_buf_get_var()
  let message_count = len(b:vimcord_messages_to_extra_data)

  for i in range(message_count - 1, 0, -1)
    let message = b:vimcord_messages_to_extra_data[i]
    if get(message, "message_id", "") ==# a:message_id
      return i
    endif
  endfor

  return -1
endfunction

function vimcord#discord#redo_reply_extmarks(reply_id, new_contents)
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

function vimcord#discord#goto_reference() range
  if len(b:vimcord_lines_to_messages) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_number = b:vimcord_lines_to_messages[a:firstline - 1]
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

  let message_number = vimcord#discord#get_message_number(reply_id)
  if message_number == -1
    " TODO: try to prepend reference contents
    echohl ErrorMsg
    echo "Replied message not in buffer!"
    echohl None
    return
  endif

  let [start_line, end_line] = vimcord#buffer#lines_by_message_number(message_number)
  call cursor(start_line + 1, 0)
endfunction
