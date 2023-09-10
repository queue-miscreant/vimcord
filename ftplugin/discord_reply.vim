setlocal nonumber
" setlocal completefunc="s:complete_reply"
exe "setlocal completefunc=" .. expand("<SID>") .. "complete_reply"

function s:complete_reply(findstart, base)
  " first invocation: find the last "@"
  if a:findstart ==# 1 && a:base ==# ""
    let start_pos = getpos(".")
    normal F@
    let match_pos = col(".")
    call cursor(start_pos[1:])

    " No @ found
    if match_pos == start_pos[2]
      return -3
    endif
    return match_pos
  endif

  " second invocations: get members
  if !(exists("g:vimcord.reply_target_data.data.server_id") && exists("g:vimcord.server_members"))
    return []
  endif

  " TODO: technically we can just query the remote plugin here
  let server_id = g:vimcord["reply_target_data"]["data"]["server_id"]
  let members = get(g:vimcord["server_members"], server_id, [])

  echom members
  return filter(members, "v:val =~ a:base")
endfunction

function s:vimcord_reply_tab(backwards)
  let insert_char = "\<tab>"
  if pumvisible()
    if a:backwards
      let insert_char = "\<c-p>"
    else
      let insert_char = "\<c-n>"
    endif
  endif

  return insert_char
endfunction

" Plugin maps
map <silent><buffer> <plug>(vimcord_push_contents) :call vimcord#push_buffer_contents()<cr>
map <silent><buffer> <plug>(vimcord_forget_buffer) <esc>:call vimcord#forget_reply_contents()<cr>
" imap <silent><buffer> <plug>(vimcord_complete_reply) <c-r>=vimcord#complete_reply()<cr>

exe "imap <buffer><silent> <plug>(vimcord_reply_tab) <c-r>=" .. expand("<SID>") .. "vimcord_reply_tab(0)<cr>"
exe "imap <buffer><silent> <plug>(vimcord_reply_tab_back) <c-r>=" .. expand("<SID>") .. "vimcord_reply_tab(1)<cr>"

" Real maps
nmap <silent><buffer> <enter> <plug>(vimcord_push_contents)
imap <silent><buffer> <enter> <esc><plug>(vimcord_push_contents)

nmap <silent><buffer> <c-c> <plug>(vimcord_forget_buffer)
imap <silent><buffer> <c-c> <esc><plug>(vimcord_forget_buffer)

imap <buffer> @ @<c-x><c-u>
imap <buffer> <tab> <plug>(vimcord_reply_tab)
imap <buffer> <s-tab> <plug>(vimcord_reply_tab_back)

" imap <silent><buffer> @ <plug>(vimcord_complete_reply)

" Autocmds
function s:window_return()
  if exists("b:vimcord_entering_buffer")
    unlet b:vimcord_entering_buffer
    return
  endif
  wincmd p
endfunction

augroup discord_reply
  autocmd WinLeave <buffer> call vimcord#forget_reply_contents()
  autocmd WinClosed <buffer> call timer_start(0, { -> vimcord#create_reply_window(1) })
  autocmd WinEnter <buffer> call timer_start(0, { -> s:window_return() })
augroup end
