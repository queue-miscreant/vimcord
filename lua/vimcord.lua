-- vimcord.lua
-- 
-- Utility functions that wrap Vimscript functions in `nvim_buf_call` and `nvim_win_call`s
-- In the future, this may be used for keeping track of buffer/channel mappings

if vimcord == nil then vimcord = {} end

local LINKS_NAMESPACE = vim.api.nvim_create_namespace("vimcord-links")
local REPLY_NAMESPACE = vim.api.nvim_create_namespace("vimcord-replies")
local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("vimcord-highlights")
vimcord.LINKS_NAMESPACE = LINKS_NAMESPACE
vimcord.REPLY_NAMESPACE = REPLY_NAMESPACE
vimcord.HIGHLIGHT_NAMESPACE = HIGHLIGHT_NAMESPACE

function vimcord.create_window(create_tab, ...)
  local buf = ...
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
  -- hold off until we've got a window to set the filetype
  vim.api.nvim_buf_set_option(buf, "filetype", "discord_messages")

  local reply_window = vim.call("vimcord#reply#create_reply_window", true)

  vim.call("win_gotoid", win)
  return buf
end

-- all
function vimcord.append_messages_to_buffer(buffer, discord_messages)
  vim.schedule(function()
    local line_count = 0
    vim.api.nvim_buf_call(buffer, function()
      local total_lines = vim.call("line", "$")
      local cursor_position = vim.call("line", ".")

      if cursor_position == 1 and total_lines == cursor_position then
        line_count = line_count - 1
      end

      for _, message in pairs(discord_messages) do
        vim.call("vimcord#buffer#append", unpack(message))
        local contents = message[1]
        line_count = line_count + #contents
      end
    end)

    local windows = vim.call("win_findbuf", buffer)
    for i = 1, #windows do
      vim.api.nvim_win_call(windows[i], function()
        vim.call("vimcord#scroll_cursor", line_count)
      end)
    end
  end)
end

-- TODO: this is coupled slightly tighter to discord since we have to find the message by its discord ID, rather than the message number
function vimcord.edit_buffer_message(buffer, discord_message, as_reply, discord_extra, highlighted)
  vim.schedule(function()
    local discord_message_id = discord_extra["message_id"]

    local added_lines = vim.api.nvim_buf_call(buffer, function()
      local message_number = vim.call("vimcord#discord#local#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end

      local ret = vim.call("vimcord#buffer#edit", message_number, discord_message, discord_extra, highlighted)
      vim.call("vimcord#discord#local#redo_reply_extmarks", discord_extra["message_id"], as_reply)

      return ret
    end)

    if added_lines then
      local windows = vim.call("win_findbuf", buffer)
      for i = 1, #windows do
        vim.api.nvim_win_call(windows[i], function()
          vim.call("vimcord#scroll_cursor", #discord_message)
        end)
      end
    end
  end)
end

-- TODO: ditto
function vimcord.delete_buffer_message(buffer, discord_message_id)
  vim.schedule(function()
    vim.api.nvim_buf_call(buffer, function()
      local message_number = vim.call("vimcord#discord#local#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end
      vim.call("vimcord#buffer#delete", message_number)
      vim.call(
        "vimcord#discord#local#redo_reply_extmarks",
        discord_message_id,
        {{"(Deleted)", "discordReply"}}
      )
    end)
  end)
end

-- TODO: discord_message_id decoupling
function vimcord.add_link_extmarks(buffer, discord_message_id, preview_extmarks, media_links, visited_links)
  vim.schedule(function()
    vim.api.nvim_buf_call(buffer, function()
      local message_number = vim.call("vimcord#discord#local#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end
      -- extmarks
      vim.call("vimcord#buffer#add_link_extmarks", message_number, preview_extmarks, visited_links)
      -- media content
      if #media_links > 0 then
        vim.call("vimcord#buffer#add_media_content", message_number, media_links)
      end
    end)
  end)
end
