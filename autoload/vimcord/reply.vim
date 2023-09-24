let s:handlers = {}

function s:try_handle(action_name)
  if exists("s:handlers." .. a:action_name)
    call s:handlers[a:action_name]()
    return 1
  endif
  return 0
endfunction

function vimcord#reply#add_handler(action_name, func)
  let s:handlers[a:action_name] = a:func
endfunction

function vimcord#reply#enter_reply_buffer(target_data, buffer_contents, ...)
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

  " Remove filename autocommands
  augroup vimcord_reply_dynamic
    autocmd!
  augroup end

  if a:0 >= 1
    call function(a:1)()
  endif

  " Set buffer attributes
  if len(a:buffer_contents) !=# 0
    call setline(1, split(a:buffer_contents, "\n"))
  endif
  startinsert!
endfunction

function vimcord#reply#push_buffer_contents()
  let target_data = get(g:vimcord, "reply_target_data", {})

  if len(target_data) ==# 0
    echohl WarningMsg
    echo "No target for action"
    echohl None
    return
  endif

  let buffer_contents = join(getbufline(
        \ g:vimcord["reply_buffer"],
        \ 1,
        \ line("$")
        \ ), "\n")

  let filenames = []
  try
    let filenames = nvim_buf_get_var(g:vimcord["reply_buffer"],
          \ "vimcord_uploaded_files")
  catch
  endtry

  let try_handle = s:try_handle(target_data["action"])
  if !try_handle
    call VimcordInvokeDiscordAction(
          \ target_data["action"],
          \ target_data["data"],
          \ { "content": buffer_contents, "filenames": filenames }
          \ )
  endif

  call vimcord#reply#forget_reply_contents()
  normal Gzb0KJ
endfunction

function vimcord#reply#forget_reply_contents()
  " Remove the status line
  if exists("g:vimcord.reply_target_data")
    " Easy mode for airline
    unlet g:vimcord["reply_target_data"]

    " Not-so-easy otherwise
    if !exists(":AirlineRefresh")
      for window in win_findbuf(g:vimcord["reply_buffer"])
        call nvim_win_set_option(window, "statusline", "")
      endfor
    endif
  endif

  try
    let cleanup_function = nvim_buf_get_var(g:vimcord["reply_buffer"], "vimcord_cleanup")
    call function(cleanup_function)()
    call nvim_buf_del_var(g:vimcord["reply_buffer"], "vimcord_cleanup")
  catch
  endtry

  " Clear the uploaded files
  call nvim_buf_set_var(g:vimcord["reply_buffer"], "vimcord_uploaded_files", [])

  wincmd p

  " Delete the reply buffer contents
  call deletebufline(g:vimcord["reply_buffer"], 1, "$")
  echo ""
endfunction

function vimcord#reply#create_reply_window(do_split)
  if exists("g:vimcord.reply_buffer")
    let buffer = g:vimcord["reply_buffer"]
  else
    let buffer = nvim_create_buf(v:false, v:true)
    let g:vimcord["reply_buffer"] = buffer
  endif

  let reply_in_current_tab = len(
        \   filter(
        \     map(win_findbuf(buffer), "win_id2tabwin(v:val)[0]"),
        \     "v:val ==# tabpagenr()"
        \   )
        \ )

  let current_window = winnr()
  if a:do_split && !reply_in_current_tab
    " Go to the bottom window
    let prev_window = current_window
    while 1
      wincmd j
      if prev_window == winnr()
        break
      endif
      prev_window = winnr()
    endwhile

    exe "below sbuffer " .. buffer
    resize 2
    setlocal winfixheight
    setlocal filetype=discord_reply
  endif

  exe current_window .. "wincmd w"
  return bufwinnr(buffer)
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
  " Remove null-terminator from echo
  let filename = system("echo " .. filename)[:-2]
  if filereadable(filename)
    " remove the filename we just inserted
    exe "normal \"_d" .. s:last_move_size .. "h"

    if !exists("b:vimcord_uploaded_files")
      let b:vimcord_uploaded_files = []
    endif
    call add(b:vimcord_uploaded_files, filename)
    echo "Appended file: '" .. filename .. "'"
  endif
endfunction

function vimcord#reply#enable_filename()
  if !exists("g:vimcord.reply_buffer") || g:vimcord["reply_buffer"] !=# bufnr()
    return
  endif

  if g:vimcord_dnd_paste_threshold > 0
    augroup vimcord_reply_dynamic
      autocmd TextChangedI <buffer> call timer_start(0, { -> s:add_drag_and_drop(getpos("."))})
      autocmd CursorMovedI <buffer> call timer_start(0, { -> s:update_cursor(getpos("."))})
    augroup end
  endif
endfunction
