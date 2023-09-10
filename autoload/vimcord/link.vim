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

function vimcord#link#open_under_cursor()
  let link = expand("<cWORD>")
  call VimcordVisitLink(link)

  for image_link_re in s:IMAGE_LINK_FORMATS
    if match(link, image_link_re) != -1
      call vimcord#link#open_image(link)
      return
    endif
  endfor

  for video_link_re in s:VIDEO_LINK_FORMATS
    if match(link, video_link_re) != -1
      call vimcord#link#open_video(link)
      return
    endif
  endfor

  let mimetype = system("curl -X HEAD -I " . shellescape(link) . " 2>/dev/null"
        \ . " | grep '^content-type:'"
        \ . " | cut -d' ' -f 2-"
        \ . " | tr -d '\\n'")

  for image_type in s:IMAGE_MIMES
    if match(mimetype, image_type) != -1
      call vimcord#link#open_image(link)
      return
    endif
  endfor

  for video_type in s:VIDEO_MIMES
    if match(mimetype, video_type) != -1
      call vimcord#link#open_video(link)
      return
    endif
  endfor

  exe "normal! \<Plug>NetrwBrowseX"
endfunction

function vimcord#link#open_most_recent()
  let prev = getcurpos()

  exe "normal $"
  let try_search = search("https\\{0,1\\}:\\/\\/.\\+\\.[^` \\x1b]\\+", 'b')
  if try_search == 0
    call setpos(".", prev)
    echo "No links found!"
    return
  endif

  call vimcord#link#open_under_cursor()

  call setpos(".", prev)
  echo ""
endfunction

function vimcord#link#open_image(link)
  call system("feh " . shellescape(a:link) . " &")
endfunction

function vimcord#link#open_video(link)
  call system("mpv " . shellescape(a:link) . " &")
endfunction
