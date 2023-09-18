let s:handlers = {}

function vimcord#action#try_handle(action_name)
  if exists("s:handlers." .. a:action_name)
    call s:handlers[a:action_name]()
    return 1
  endif
  return 0
endfunction

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

function s:echo(message, ...)
  if a:0 >= 1
    exe "echohl " .. a:1
  else
    echohl ErrorMsg
  endif
  echo a:message
  echohl None
endfunction

function! s:remove_vimcord_autocmds()
  augroup vimcord_open_channel
    autocmd!
  augroup end
endfunction

function! s:update_server_suggestions()
  if line(".") > 1
    call deletebufline(bufnr(), 2, "$")
    normal $
  endif

  let line = getline(1)
  let b:vimcord_fuzzy_match_results = line ==# ""
        \ ? b:vimcord_fuzzy_match
        \ : matchfuzzy(b:vimcord_fuzzy_match, line)
  call complete(col("."), b:vimcord_fuzzy_match_results)
endfunction

function vimcord#action#open_channel() range
  " Get the channel name by name
  " TODO: investigate a better way of doing this (new split, etc)
  " Update suggestions when typing channel name

  call s:enter_reply_buffer({
        \   "data": {},
        \   "action": "find_discord_channel"
        \ },
        \ "")
  let b:vimcord_fuzzy_match = values(get(g:vimcord, "channel_names", {}))
  let b:vimcord_fuzzy_match_results = []

  " Option record
  let b:vimcord_previous_completeopt = &completeopt
  let b:vimcord_previous_pumheight = &pumheight
  set completeopt+=noinsert,menuone
  let &pumheight = g:vimcord_max_suggested_servers

  " Automatic completion/autocommand removal
  augroup vimcord_open_channel
    autocmd!
    autocmd TextchangedI <buffer> call s:update_server_suggestions()
    autocmd WinLeave <buffer> call s:remove_vimcord_autocmds()
  augroup end
endfunction

function s:handlers.find_discord_channel()
  " Try the first fuzzy result
  let channel_name = get(b:vimcord_fuzzy_match_results, 0, "")
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
    echohl ErrorMsg
    echo "Channel name not found"
    echohl None
    return
  endif
  echo ""

  call timer_start(0, { ->
        \   s:enter_reply_buffer({
        \     "data": { "channel_id": channel_id },
        \     "action": "message"
        \   },
        \   "")
        \ })
endfunction
