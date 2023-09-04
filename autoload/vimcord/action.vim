function vimcord#action#open_reply(is_reply) range
  if len(b:discord_content) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]
  let content = input("")
  if content !=# ""
    call VimcordInvokeDiscordAction("message", message_data , content, a:is_reply)
  endif
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

function vimcord#action#edit() range
  if len(b:discord_content) <= a:firstline - 1
    echohl ErrorMsg
    echo "No message under cursor"
    echohl None
    return
  endif

  let message_data = b:discord_content[a:firstline - 1]
  " TODO: only edit when the author is the same as the user
  let content = input("", message_data["raw_message"])
  if content ==# ""
    call VimcordInvokeDiscordAction("delete", message_data)
  else
    call VimcordInvokeDiscordAction("edit", message_data, content)
  endif
endfunction

function vimcord#action#write_channel() range
  " TODO: jesus this is bad
  let discord_servers = VimcordInvokeDiscordAction("get_servers")

  function! Completer(arglead, cmdline, cursorpos) closure
    return filter(discord_servers, { _, x -> x =~ a:arglead })
  endfunction

  let channel_name = input("Server: ", "", "customlist,Completer")
  if index(discord_servers, channel_name) == -1
    echo "Server name not found"
    return
  endif
  let content = input("Message: ")
  if content !=# ""
    call VimcordInvokeDiscordAction("try_post_server", channel_name, content)
  endif
endfunction

function vimcord#action#reconnect()
  call VimcordInvokeDiscordAction("try_reconnect")
endfunction
