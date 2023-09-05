let s:ats = []
function! s:complete_ats(arglead, cmdline, cursorpos)
  let last_at = strridx(a:cmdline, "@", a:cursorpos)
  if last_at !=# -1
    let atrange = a:cmdline[last_at+1:a:cursorpos]
    return map(
          \ filter(copy(s:ats), { _, v -> stridx(v, atrange) == 0 }), 
          \ { _, v -> a:cmdline[:last_at] . v .  a:cmdline[last_at+2:]})
  endif
  return []
endfunction


function s:echo(text, ...)
  if a:0 >= 2
    execute "echohl " .. a:2
  endif
  echo a:text
  echohl None
endfunction

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

  if message_data["server_id"] !=# v:null
    let s:ats = b:vimcord_server_members[message_data["server_id"]]
  endif

  " Wrapping this in try to ignore ctrl-c
  try
    let content = input("", "", "customlist," . expand("<SID>") . "complete_ats")
    call timer_start(0, { -> s:echo("") })
    if content !=# ""
      call VimcordInvokeDiscordAction("message", message_data, content, a:is_reply)
      normal Gzb0
    endif
  catch /Vim:Interrupt/
  endtry

  let s:ats = []

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

function vimcord#action#edit_end(raw_data, message_data)
  call timer_start(
        \ 0,
        \ { -> s:edit_end(a:raw_data, a:message_data) }
        \ )
endfunction

function s:edit_end(raw_data, message_data)
  try
    let b:vimcord_target_channel = b:vimcord_channel_names[a:message_data["channel_id"]]

    if exists(":AirlineRefresh")
      AirlineRefresh!
      redrawstatus
    endif
  catch
  endtry

  if a:message_data["server_id"] !=# v:null
    let s:ats = b:vimcord_server_members[a:message_data["server_id"]]
  endif

  try
    let content = input("", "", "customlist," . expand("<SID>") . "complete_ats")
    call timer_start(0, { -> s:echo("") })
    if content ==# ""
      call VimcordInvokeDiscordAction("delete", a:message_data["message_id"])
    else
      call VimcordInvokeDiscordAction("edit", a:message_data, content)
    endif
  catch /Vim:Interrupt/
  endtry

  let s:ats = []

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
  try
    let channel_name = input("Channel: ", "", "customlist,Completer")
  catch /Vim:Interrupt/
    return
  endtry

  if channel_name ==# ""
    return
  endif

  " Reverse-lookup for id
  let channel_id = ""
  for [id, name] in items(b:vimcord_channel_names)
    if name ==# channel_name
      let channel_id = id
      break
    endif
  endfor
  if channel_id ==# ""
    call timer_start(0, { -> s:echo("Server name not found", "ErrorMsg") })
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

  " TODO
  " let ats = []
  " if message_data["server_id"] !=# v:null
  "   let ats = copy(b:vimcord_server_members[message_data["server_id"]])
  " endif
  " function! Ats(arglead, cmdline, cursorpos) closure
  "   let last_at = strridx(a:cmdline, "@", a:cursorpos)
  "   if last_at !=# -1
  "     let atrange = a:cmdline[last_at+1:a:cursorpos]
  "     let ret = map(filter(ats, { _, v -> stridx(v, atrange) == 0 }), { _, v -> a:cmdline[:last_at-1] . v .  a:cmdline[last_at+1:]})
  "     return ret
  "   endif
  "   return []
  " endfunction

  try
    " let content = input("", a:raw_data, "customlist,Ats")
    let content = input("")
    call timer_start(0, { -> s:echo("") })
    if content !=# ""
      call VimcordInvokeDiscordAction("try_post_channel", channel_id, content)
    endif
  catch /Vim:Interrupt/
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
