setlocal nonumber
setlocal wrap
setlocal linebreak
setlocal breakindent

function s:complete_reply()
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

let b:complete_reply = function("s:complete_reply")

" Plugin maps
nmap <silent><buffer> <plug>(vimcord_push_contents) :call vimcord#push_buffer_contents()<cr>
nmap <silent><buffer> <plug>(vimcord_forget_buffer) :call vimcord#forget_reply_contents()<cr>

" Real maps
nmap <silent><buffer> <enter> <plug>(vimcord_push_contents)
imap <silent><buffer> <enter> <esc><plug>(vimcord_push_contents)

nmap <silent><buffer> <c-c> <plug>(vimcord_forget_buffer)
imap <silent><buffer> <c-c> <esc><plug>(vimcord_forget_buffer)
nmap <silent><buffer> <esc> <plug>(vimcord_forget_buffer)

imap <buffer><silent> <tab> <c-r>= pumvisible() ? "\<lt>c-n>" : "\<lt>tab>"<cr>
imap <buffer><silent> <s-tab> <c-r>= pumvisible() ? "\<lt>c-p>" : "\<lt>s-tab>"<cr>

imap <buffer> @ @<c-r>=b:complete_reply()<cr>

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

  " Assume drag and drop content is shell-escaped already
  let filename = system("echo " .. filename)
  if filereadable(filename[:-2])
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
  autocmd!
  autocmd WinLeave <buffer> call vimcord#forget_reply_contents()
  autocmd WinClosed <buffer> call timer_start(0, { -> vimcord#create_reply_window(1) })
  autocmd WinEnter <buffer> call timer_start(0, { -> s:window_return() })

  if g:vimcord_dnd_paste_threshold > 0
    autocmd TextChangedI <buffer> call timer_start(0, { -> s:add_drag_and_drop(getpos("."))})
    autocmd CursorMovedI <buffer> call timer_start(0, { -> s:update_cursor(getpos("."))})
  endif
augroup end
