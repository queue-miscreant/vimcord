function vimcord#action#open_reply(is_reply) range
  if len(b:discord_content) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]

  let prev_cursorline = &cursorline
  if a:is_reply
    if !exists("message_data.message_id")
      return
    endif
    setlocal cursorline
  endif

  if exists("b:vimcord_channel_names." . message_data["channel_id"])
    let b:vimcord_target_channel = b:vimcord_channel_names[message_data["channel_id"]]

    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  endif

  " Wrapping this in try to ignore ctrl-c
  try
    let content = input({
          \ "prompt": "",
          \ "cancelreturn": ""
          \ })
    if content !=# ""
      call VimcordInvokeDiscordAction("message", message_data, content, a:is_reply)
      normal Gzb0
    endif
  catch
  endtry

  if a:is_reply
    let &cursorline = prev_cursorline
  endif

  try
    unlet b:vimcord_target_channel
    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry
endfunction

function vimcord#action#delete() range
  if len(b:discord_content) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]
  call VimcordInvokeDiscordAction("delete", message_data)
endfunction

" TODO: split this in two: request raw_message from the plugin and place it in
" input()
function vimcord#action#edit_start() range
  if len(b:discord_content) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]
  call VimcordInvokeDiscordAction("tryedit", message_data)
endfunction

function vimcord#action#edit_end(raw_data, message_id, channel_id)
  call timer_start(
        \ 0,
        \ { -> s:edit_end(a:raw_data, a:message_id, a:channel_id) }
        \ )
endfunction

function s:edit_end(raw_data, message_id, channel_id)
  try
    let b:vimcord_target_channel = b:vimcord_channel_names[a:channel_id]

    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry

  try
    let content = input("", a:raw_data)
    if content ==# ""
      call VimcordInvokeDiscordAction("delete", a:message_id)
    else
      call VimcordInvokeDiscordAction("edit", a:message_id, content)
    endif
  catch
  endtry

  try
    unlet b:vimcord_target_channel

    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry
endfunction

function vimcord#action#write_channel() range
  function! Completer(arglead, cmdline, cursorpos) closure
    return filter(values(b:vimcord_channel_names), { _, x -> x =~ a:arglead })
  endfunction

  " Get the channel name by name
  let channel_name = input("Channel: ", "", "customlist,Completer")

  " Reverse-lookup for id
  let channel_id = ""
  for [id, name] in items(b:vimcord_channel_names)
    if name ==# channel_name
      let channel_id = id
      break
    endif
  endfor
  if channel_id ==# ""
    echo "\nServer name not found"
    return
  endif

  " Set status
  try
    let b:vimcord_target_channel = b:vimcord_channel_names[channel_id]

    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry

  try
    let content = input("")
    if content !=# ""
      call VimcordInvokeDiscordAction("try_post_channel", channel_id, content)
    endif
  catch
  endtry

  try
    unlet b:vimcord_target_channel
    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry
endfunction

function vimcord#action#reconnect()
  call VimcordInvokeDiscordAction("try_reconnect")
endfunction
