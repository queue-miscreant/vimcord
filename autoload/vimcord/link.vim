let s:IMAGE_LINK_FORMATS = []
let s:VIDEO_LINK_FORMATS = [
      \ "youtube.com/watch",
      \ "youtube.com/shorts",
      \ "youtu.be/",
      \ "tiktok.com/t/",
      \ "tenor.com/view"
      \ ]

let s:IMAGE_MIMES = ["image/png", "image/jpeg"]
let s:VIDEO_MIMES = ["image/gif", "video/.*"]

function vimcord#link#open_media_under_cursor()
  let startline = line(".") - 1
  let message = b:discord_content[startline]

  if !exists("message.message_id")
    return
  endif

  let last_message = message
  while 1
    let startline += 1
    if !exists("b:discord_content[startline]") ||
          \ get(b:discord_content[startline], "message_id", "") !=# message["message_id"]
      break
    endif
    let last_message = b:discord_content[startline]
  endwhile

  if exists("last_message.media_content")
    for link in get(last_message, "media_content", [])
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
  for image_link_re in s:IMAGE_LINK_FORMATS
    if match(link, image_link_re) != -1
      call vimcord#link#open_image(a:link)
      return
    endif
  endfor

  for video_link_re in s:VIDEO_LINK_FORMATS
    if match(a:link, video_link_re) != -1
      call vimcord#link#open_video(a:link)
      return
    endif
  endfor

  let mimetype = system("curl -X HEAD -I " . shellescape(a:link) . " 2>/dev/null"
        \ . " | grep '^content-type:'"
        \ . " | cut -d' ' -f 2-"
        \ . " | tr -d '\\n'")

  for image_type in s:IMAGE_MIMES
    if match(mimetype, image_type) != -1
      call vimcord#link#open_image(a:link)
      return
    endif
  endfor

  for video_type in s:VIDEO_MIMES
    if match(mimetype, video_type) != -1
      call vimcord#link#open_video(a:link)
      return
    endif
  endfor

  if use_default
    exe "normal! \<Plug>NetrwBrowseX"
  endif
  echo ""
endfunction

function vimcord#link#open_most_recent(only_media)
  let prev = getcurpos()

  normal $
  let try_search = search("https\\{0,1\\}:\\/\\/.\\+\\.[^` \\x1b]\\+", 'bz')
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
  call system("feh " . shellescape(a:link) . " &")
endfunction

function vimcord#link#open_video(link)
  echo "Playing video..."
  call system("mpv " . shellescape(a:link) . " &")
endfunction
