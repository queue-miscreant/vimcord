if vimcord == nil then vimcord = {} end

local LINKS_NAMESPACE = vim.api.nvim_create_namespace("vimcord-links")
local REPLY_NAMESPACE = vim.api.nvim_create_namespace("vimcord-replies")
vimcord.LINKS_NAMESPACE = LINKS_NAMESPACE
vimcord.REPLY_NAMESPACE = REPLY_NAMESPACE

function vimcord.create_window(create_tab, ...)
  local buf = ...
  -- get a new buffer
  if buf == nil then
    buf = vim.api.nvim_create_buf(false, true)
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

  local reply_window = vim.call("vimcord#create_reply_window", true)
  -- set options for new buffer/window
  vim.api.nvim_buf_set_var(buf, "vimcord_lines_to_messages", {})
  vim.api.nvim_buf_set_var(buf, "vimcord_messages_to_extra_data", {})
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "discord_messages")

  -- ditto for the reply window
  vim.api.nvim_buf_set_var(vim.g.vimcord.reply_buffer, "vimcord_target_buffer", buf)

  vim.call("win_gotoid", win)
  return buf
end

-- all
function vimcord.append_to_buffer(buffer, discord_message, reply, discord_extra)
  vim.schedule(function()
    vim.api.nvim_buf_call(buffer, function()
      vim.call("vimcord#buffer#append", discord_message, reply, discord_extra)
    end)

    local windows = vim.call("win_findbuf", buffer)
    for i = 1, #windows do
      vim.api.nvim_win_call(windows[i], function()
        vim.call("vimcord#scroll_cursor", #discord_message)
      end)
    end
  end)
end

function vimcord.append_many_to_buffer(buffer, discord_messages)
  vim.schedule(function()
    local line_count = 0
    vim.api.nvim_buf_call(buffer, function()
      for _, message in pairs(discord_messages) do
        vim.call("vimcord#buffer#append", unpack(message))
        local contents = message[1]
        line_count = line_count + #contents
      end
    end)

    local windows = vim.call("win_findbuf", buffer)
    for i = 1, #windows do
      vim.api.nvim_win_call(windows[i], function()
        vim.call("vimcord#scroll_cursor", line_count - 1)
      end)
    end
  end)
end

-- TODO: this is coupled slightly tighter to discord since we have to find the message by its discord ID, rather than the message number
function vimcord.edit_buffer_message(buffer, discord_message, as_reply, discord_extra)
  vim.schedule(function()
    local discord_message_id = discord_extra["message_id"]

    local added_lines = vim.api.nvim_buf_call(buffer, function()
      local message_number = vim.call("vimcord#discord#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end

      local ret = vim.call("vimcord#buffer#edit", message_number, discord_message, discord_extra)
      vim.call("vimcord#discord#redo_reply_extmarks", discord_extra["message_id"], as_reply)

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
      local message_number = vim.call("vimcord#discord#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end
      vim.call("vimcord#buffer#delete", message_number)
      vim.call(
        "vimcord#discord#redo_reply_extmarks",
        discord_message_id,
        {{"(Deleted)", "discordReply"}}
      )
    end)
  end)
end

-- TODO: use extmark highlights instead of syntax
function vimcord.recolor_visited_links(buffer, unvisited)
  vim.schedule(function()
    vim.api.nvim_buf_set_option(buffer, "modifiable", true)

    --fetch the cursor
    local windows = vim.call("win_findbuf", buffer)
    local cursor = vim.api.nvim_win_get_cursor(windows[1])

    -- even in vimscript, this would be an execute command, so I'm not torn up about it being here
    for _, j in pairs(unvisited) do
      local escape_slashes = j:gsub("/", "\\/")
      pcall(function()
        vim.cmd(
          "keeppatterns %sno/\\(\\%x1B\\)100 \\(" .. escape_slashes ..
          " \\%x1B\\)/\\1VL \\2/g"
        )
      end)
    end

    --and restore it
    vim.api.nvim_win_set_cursor(windows[1], cursor)

    vim.api.nvim_buf_set_option(buffer, "modifiable", false)
  end)
end

-- TODO: discord_message_id decoupling
function vimcord.add_link_extmarks(buffer, discord_message_id, extmark_content, media_links)
  vim.schedule(function()
    vim.api.nvim_buf_call(buffer, function()
      local message_number = vim.call("vimcord#discord#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end
      -- extmarks
      local line_number = vim.call("vimcord#buffer#add_link_extmarks", message_number, extmark_content)
      -- media content
      if line_number > 0 then
        vim.call("vimcord#buffer#add_media_content", line_number, media_links)
      end
    end)
  end)
end
