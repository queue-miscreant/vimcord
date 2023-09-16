function s:enter_reply_buffer(target_data, buffer_contents)
  " Set status by peeking into target data
  if exists("a:target_data.data.channel_id")
    " XXX: Interface with other status line plugins?
    " Not-so-easy otherwise
    if !exists(":AirlineRefresh")
      for window in win_findbuf(g:vimcord["reply_buffer"])
        call nvim_win_set_option(window, "statusline", VimcordShowChannel())
      endfor
    endif
  endif

  let g:vimcord["reply_target_data"] = a:target_data

  " Enter reply buffer
  call nvim_buf_set_var(g:vimcord["reply_buffer"], "vimcord_entering_buffer", 1)
  let target_window = bufwinnr(g:vimcord["reply_buffer"])
  if target_window == -1
    " TODO: consider opening the reply window instead
    return
  endif
  exe target_window .. "wincmd w"

  " Set buffer attributes
  if len(a:buffer_contents) !=# 0
    call setline(1, a:buffer_contents)
  endif
  " TODO: set completion
  " TODO: remove completion onwinleave
  startinsert!
endfunction

function vimcord#action#open_reply(is_reply) range
  if len(b:vimcord_lines_to_messages) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_number = b:vimcord_lines_to_messages[a:firstline - 1]
  let message_data = copy(b:vimcord_messages_to_extra_data[message_number])
  let message_data["is_reply"] = a:is_reply

  if a:is_reply
    if !exists("message_data.message_id")
      echohl ErrorMsg
      echo "Cannot reply to the selected message"
      echohl None
      return
    endif
    setlocal cursorline
  endif

  call s:enter_reply_buffer({
        \   "data": message_data,
        \   "action": "message"
        \ },
        \ "")
endfunction

function vimcord#action#delete() range
  if len(b:vimcord_lines_to_messages) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_number = b:vimcord_lines_to_messages[a:firstline - 1]
  let message_data = copy(b:vimcord_messages_to_extra_data[message_number])
  call VimcordInvokeDiscordAction("delete", message_data)
endfunction

function vimcord#action#edit_start() range
  if len(b:vimcord_lines_to_messages) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_number = b:vimcord_lines_to_messages[a:firstline - 1]
  let message_data = copy(b:vimcord_messages_to_extra_data[message_number])
  call VimcordInvokeDiscordAction("try_edit", message_data)
endfunction

function s:do_edit(raw_data, message_data)
  call s:enter_reply_buffer({
          \   "data": a:message_data,
          \   "action": "do_edit"
          \ },
          \ a:raw_data
          \ )
endfunction

function vimcord#action#do_edit(raw_data, message_data)
  call timer_start(0,
        \ { -> s:do_edit(a:raw_data, a:message_data) }
        \ )
endfunction

function vimcord#action#reconnect()
  call VimcordInvokeDiscordAction("try_reconnect")
endfunction


function! s:complete_channel(arglead, cmdline, cursorpos)
  " TODO: fuzzier channel search
  return filter(values(get(g:vimcord, "channel_names", {})), { _, x -> x =~ a:arglead })
endfunction

function s:echo(message, ...)
  if a:0 >= 1
    exe "echohl " .. a:1
  else
    echohl ErrorMsg
  endif
  echo a:message
  echohl None
endfunction

function vimcord#action#open_channel() range
  " Get the channel name by name
  " TODO: investigate a better way of doing this (new split, etc)
  try
    let channel_name = input("Channel: ", "", "customlist," .. expand("<SID>") .. "complete_channel")
  catch /Vim:Interrupt/
    return
  endtry

  if channel_name ==# ""
    return
  endif

  " Reverse-lookup for id
  let channel_id = ""
  for [id, name] in items(get(g:vimcord, "channel_names", {}))
    if name ==# channel_name
      let channel_id = id
      break
    endif
  endfor
  if channel_id ==# ""
    call timer_start(0, { -> s:echo("Channel name not found") })
    return
  endif
  echo ""

  call s:enter_reply_buffer({
        \   "data": { "channel_id": channel_id },
        \   "action": "message"
        \ },
        \ "")
endfunction
