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

  " XXX: technically we can just query the remote plugin here
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
nmap <silent><buffer> <plug>(vimcord_push_contents) :call vimcord#push_buffer_contents()<cr>
nmap <silent><buffer> <plug>(vimcord_forget_buffer) :call vimcord#forget_reply_contents()<cr>
" imap <silent><buffer> <plug>(vimcord_complete_reply) <c-r>=vimcord#complete_reply()<cr>

exe "imap <buffer><silent> <plug>(vimcord_reply_tab) <c-r>=" .. expand("<SID>") .. "vimcord_reply_tab(0)<cr>"
exe "imap <buffer><silent> <plug>(vimcord_reply_tab_back) <c-r>=" .. expand("<SID>") .. "vimcord_reply_tab(1)<cr>"

" Real maps
nmap <silent><buffer> <enter> <plug>(vimcord_push_contents)
imap <silent><buffer> <enter> <esc><plug>(vimcord_push_contents)

nmap <silent><buffer> <c-c> <plug>(vimcord_forget_buffer)
imap <silent><buffer> <c-c> <esc><plug>(vimcord_forget_buffer)
nmap <silent><buffer> <esc> <plug>(vimcord_forget_buffer)

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

let s:last_move_size = -1
let s:last_cursor_position = [0,0,0,0]
" Callback for cursor moved. Keep track of large movements in insert mode
" For some reason, InsertCharPre isn't good enough to capture multiple bytes,
" so this hack is needed
function s:update_cursor(position)
  let s:last_move_size = a:position[2] - s:last_cursor_position[2]
  " Disregard if we're on another line now or inserted too little
  " If this is the first line, then we're technically at line 0
  let last_cursor_line = s:last_cursor_position[1] + (s:last_cursor_position[1] ==# 0)
  if last_cursor_line !=# a:position[1] ||
        \ s:last_move_size < g:vimcord_dnd_paste_threshold
    let s:last_move_size = -1
  endif
  let s:last_cursor_position = a:position
endfunction

function s:add_drag_and_drop(position)
  if s:last_move_size < 0
    return
  endif

  " Get the (trimmed) inserted content
  let start_position = max([0, a:position[2] - s:last_move_size - 1])
  let insert_content = getline(".")[start_position:a:position[2]]
  let filename = trim(insert_content)

  " Konsole inserts filenames with spaces using single quotes.
  " I assume there are ones out there which use double quotes
  if filename[0] ==# filename[-1:] && (filename[0] ==# "'" || filename[0] ==# "\"")
    let filename = filename[1:-2]
  endif
  echom filename
  if filereadable(filename)
    " remove the filename we just inserted
    exe "normal \"_d" .. s:last_move_size .. "h"

    if !exists("b:vimcord_uploaded_files")
      let b:vimcord_uploaded_files = []
    endif
    call add(b:vimcord_uploaded_files, filename)
    echo "Appended file: " .. filename
  endif
endfunction

augroup discord_reply
  autocmd WinLeave <buffer> call vimcord#forget_reply_contents()
  autocmd WinClosed <buffer> call timer_start(0, { -> vimcord#create_reply_window(1) })
  autocmd WinEnter <buffer> call timer_start(0, { -> s:window_return() })

  if g:vimcord_dnd_paste_threshold > 0
    autocmd TextChangedI <buffer> call timer_start(0, { -> s:add_drag_and_drop(getpos("."))})
    autocmd CursorMovedI <buffer> call timer_start(0, { -> s:update_cursor(getpos("."))})
  endif
augroup end
