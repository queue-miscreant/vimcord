-- buffer.lua
--
-- Common (nearly virtual) functions which interact with the vim functions (primarily through
-- window/buffer calls), but do not interact directly with Discord data.

buffer = {}

function buffer.create_window(create_tab, buf)
  -- get a new buffer
  if buf == nil then
    buf = vim.call("vimcord#buffer#create_buffer")
  end
  -- decide which window to use
  local win
  if not create_tab then
    local current_buffer = vim.call("getbufinfo", vim.call("bufnr"))[1]
    if current_buffer.linecount == 1 and current_buffer.changed == 0 and vim.call("getline", 1) == "" then
      win = vim.api.nvim_get_current_win()
    else
      vim.cmd("split")
      win = vim.api.nvim_get_current_win()
    end
  else
    vim.cmd("tabnew")
    win = vim.api.nvim_get_current_win()
  end
  -- cursor is currently in the new window
  vim.api.nvim_win_set_buf(win, buf)

  local reply_window = vim.call("vimcord#reply#create_reply_window", true)

  vim.call("win_gotoid", win)
  return buf
end

-- all
function buffer.append_messages_to_buffer(messages)
  local line_count = 0
  local total_lines = vim.call("line", "$")
  local cursor_position = vim.call("line", ".")

  if cursor_position == 1 and total_lines == cursor_position then
    line_count = line_count - 1
  end

  for _, message in pairs(messages) do
    vim.call("vimcord#buffer#append", unpack(message))
    local contents = message[1]
    line_count = line_count + #contents
  end

  local windows = vim.call("win_findbuf", vim.call("bufnr"))
  for i = 1, #windows do
    vim.api.nvim_win_call(windows[i], function()
      vim.call("vimcord#buffer#scroll_cursor", line_count)
    end)
  end
end

function buffer.edit_buffer_message(message_number, message_content, extra, highlighted)
  local added_lines = vim.call("vimcord#buffer#edit", message_number, message_content, extra, highlighted)

  if added_lines then
    local windows = vim.call("win_findbuf", vim.call("bufnr"))
    for i = 1, #windows do
      vim.api.nvim_win_call(windows[i], function()
        vim.call("vimcord#buffer#scroll_cursor", #message_content)
      end)
    end
  end
end

function buffer.delete_buffer_message(message_number)
  vim.call("vimcord#buffer#delete", message_number)
end

function buffer.add_link_extmarks(message_number, preview_extmarks, media_links, visited_links)
  -- extmarks
  vim.call("vimcord#buffer#add_link_extmarks", message_number, preview_extmarks, visited_links)
  -- media content
  if #media_links > 0 then
    vim.call("vimcord#buffer#add_media_content", message_number, media_links)
  end
end

return buffer
