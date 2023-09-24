" discord.vim
"
" Functions relating Discord-identifying data, stored in b:vimcord_messages_to_extra_data
" Fields stored here include channel, message, and server IDs
"
" Also provides function for reply extmark manipulation

function vimcord#discord#local#add_extra_data(extra_data)
  call extend(g:vimcord, a:extra_data)
endfunction

function vimcord#discord#local#set_connection_state(ready, not_connected, is_logged_in)
  let g:vimcord["discord_ready"] = a:ready
  let g:vimcord["discord_not_connected"] = a:not_connected
  let g:vimcord["discord_logged_in"] = a:is_logged_in
  redrawstatus
  call vimcord#discord#local#start_connection_timer()
endfunction

function vimcord#discord#local#start_connection_timer()
  let connection_timer = get(g:vimcord, "connection_timer", -1)
  if connection_timer < 0 && exists("g:vimcord.discord_ready") && g:vimcord["discord_ready"]
    let g:vimcord["connection_timer"] = timer_start(
          \ g:vimcord_connection_refresh_interval_seconds * 1000,
          \ "vimcord#discord#local#refresh_connection",
          \ {'repeat': -1})
  endif
endfunction

function vimcord#discord#local#stop_connection_timer()
  let connection_timer = get(g:vimcord, "connection_timer", -1)
  if connection_timer >= 0
    call timer_stop(connection_timer)
    let g:vimcord["connection_timer"] = -1
  endif
endfunction

function vimcord#discord#local#refresh_connection(...)
  try
    call VimcordInvokeDiscordAction("get_connection_state")
  catch
    " Errors should only happen when the plugin no longer exists
    echohl ErrorMsg
    echom "Could not retrieve connection state! Stopping timer..."
    echohl None

    call vimcord#discord#local#stop_connection_timer()
  endtry
endfunction

function vimcord#discord#local#get_message_number(message_id)
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

function vimcord#discord#local#redo_reply_extmarks(reply_id, new_contents)
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

function vimcord#discord#local#goto_reference() range
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

  let message_number = vimcord#discord#local#get_message_number(reply_id)
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

function vimcord#discord#local#complete_reply()
  if !(exists("g:vimcord.reply_target_data.data.server_id"))
    return ""
  endif

  let prevcomplete = &completeopt
  set completeopt+=noinsert,noselect

  let server_id = g:vimcord["reply_target_data"]["data"]["server_id"]
  let members = VimcordInvokeDiscordAction("get_server_members", server_id)
  call complete(col("."), members)

  let &completeopt = prevcomplete

  return ""
endfunction
