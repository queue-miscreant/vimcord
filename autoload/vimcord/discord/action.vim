" Typical Discord buffer, which completes @s and supports file uploads
function s:buffer_with_ats()
  imap <buffer> @ @<c-r>=vimcord#discord#local#complete_reply()<cr>
  let b:vimcord_cleanup = "vimcord#discord#action#cleanup_buffer_with_ats"

  call vimcord#reply#enable_filename()
endfunction

function vimcord#discord#action#cleanup_buffer_with_ats()
  call nvim_buf_del_keymap(g:vimcord["reply_buffer"], "i", "@")
endfunction

function vimcord#discord#action#open_reply(is_reply) range
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

  call vimcord#reply#enter_reply_buffer({
        \   "data": message_data,
        \   "action": "message"
        \ },
        \ "",
        \ function("s:buffer_with_ats"))
endfunction

" Delete Discord message -------------------------------------------------------
function vimcord#discord#action#delete() range
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

" Edit Discord message ---------------------------------------------------------
function vimcord#discord#action#edit_start() range
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
  call vimcord#reply#enter_reply_buffer({
          \   "data": a:message_data,
          \   "action": "do_edit"
          \ },
          \ a:raw_data,
          \ function("s:buffer_with_ats"))
endfunction

function vimcord#discord#action#do_edit(raw_data, message_data)
  call timer_start(0,
        \ { -> s:do_edit(a:raw_data, a:message_data) }
        \ )
endfunction

function vimcord#discord#action#reconnect()
  call VimcordInvokeDiscordAction("try_reconnect")
endfunction


" Open channel by name ---------------------------------------------------------
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

" Discord server suggestions
function s:server_suggestions()
  " TODO: this could be dynamic
  let b:vimcord_fuzzy_match = values(get(g:vimcord, "channel_names", {}))
  let b:vimcord_fuzzy_match_results = []

  " Option record
  let b:vimcord_previous_completeopt = &completeopt
  let b:vimcord_previous_pumheight = &pumheight
  set completeopt+=noinsert,menuone
  let &pumheight = g:vimcord_max_suggested_servers

  " Automatic completion
  augroup vimcord_reply_dynamic
    autocmd TextchangedI <buffer> call s:update_server_suggestions()
  augroup end

  let b:vimcord_cleanup = "vimcord#discord#action#cleanup_server_suggestions"
endfunction

function vimcord#discord#action#cleanup_server_suggestions()
  " Restore fuzzy completion data
  try
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_fuzzy_match")
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_fuzzy_match_results")
    call nvim_set_option(
          \ "completeopt",
          \ nvim_buf_get_var(g:vimcord["reply_buffer"], "vimcord_previous_completeopt")
          \ )
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
    call nvim_set_option(
          \ "pumheight",
          \ nvim_buf_get_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
          \ )
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_previous_pumheight")
  catch
  endtry
endfunction

function vimcord#discord#action#open_channel() range
  " Get the channel name by name, updating suggestions when typing channel name
  call vimcord#reply#enter_reply_buffer({
        \   "data": {},
        \   "action": "find_discord_channel"
        \ },
        \ "",
        \ function("s:server_suggestions"))
endfunction

function s:find_discord_channel()
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
        \   vimcord#reply#enter_reply_buffer({
        \     "data": { "channel_id": channel_id },
        \     "action": "message"
        \   },
        \   "",
        \   function("s:buffer_with_ats"))
        \ })
endfunction

call vimcord#reply#add_handler("find_discord_channel", function("s:find_discord_channel"))