function vimcord#link#open_media_under_cursor()
  let startline = line(".") - 1
  let message_number = b:vimcord_lines_to_messages[startline]
  let message = b:vimcord_messages_to_extra_data[message_number]

  if !exists("message.message_id")
    return
  endif

  if exists("message.media_content")
    for link in get(message, "media_content", [])
      call s:open_media(link, 0)
    endfor
  endif
endfunction

function vimcord#link#open_under_cursor(only_media)
  if a:only_media
    call vimcord#link#open_media_under_cursor()
    return
  endif

  let link = expand("<cWORD>")
  call VimcordVisitLink(link)
  call s:open_media(link, 1)
endfunction

function s:open_media(link, use_default)
  for image_link_re in g:vimcord_image_link_formats
    if match(link, image_link_re) != -1
      call vimcord#link#open_image(a:link)
      return
    endif
  endfor

  for video_link_re in g:vimcord_video_link_formats
    if match(a:link, video_link_re) != -1
      call vimcord#link#open_video(a:link)
      return
    endif
  endfor

  let mimetype = system("curl -X HEAD -I " . shellescape(a:link) . " 2>/dev/null"
        \ . " | grep '^content-type:'"
        \ . " | cut -d' ' -f 2-"
        \ . " | tr -d '\\n'")

  for image_type in g:vimcord_image_mimes
    if match(mimetype, image_type) != -1
      call vimcord#link#open_image(a:link)
      return
    endif
  endfor

  for video_type in g:vimcord_video_mimes
    if match(mimetype, video_type) != -1
      call vimcord#link#open_video(a:link)
      return
    endif
  endfor

  if a:use_default
    exe "normal! \<Plug>NetrwBrowseX"
  endif
  echo ""
endfunction

function vimcord#link#open_most_recent(only_media)
  let prev = getcurpos()

  " scroll to the last line of the message
  let current_message = b:vimcord_lines_to_messages[line(".") - 1]
  while 1
    let next_message = get(b:vimcord_lines_to_messages, line("."), -1)
    if next_message !=# current_message
      break
    endif
    normal! j
  endwhile

  " TODO: search does not get last match, even with z flag with cursor at line end
  normal $
  let try_search = search("https\\{0,1\\}:\\/\\/.\\+\\.[^` \\x1b]\\+", 'b')
  if try_search == 0
    call setpos(".", prev)
    echo "No links found!"
    return
  endif

  call vimcord#link#open_under_cursor(a:only_media)

  call setpos(".", prev)
endfunction

function vimcord#link#open_image(link)
  echo "Opening image..."
  call system(g:vimcord_image_opener . " " . shellescape(a:link) . " &")
endfunction

function vimcord#link#open_video(link)
  echo "Playing video..."
  call system(g:vimcord_video_opener . " " . shellescape(a:link) . " &")
endfunction
