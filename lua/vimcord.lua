if vimcord == nil then vimcord = {} end

local LINKS_NAMESPACE = vim.api.nvim_create_namespace("vimcord-links")
local REPLY_NAMESPACE = vim.api.nvim_create_namespace("vimcord-replies")
vimcord.LINKS_NAMESPACE = LINKS_NAMESPACE
vimcord.REPLY_NAMESPACE = REPLY_NAMESPACE

function vimcord.create_window(no_init)
  -- get a new buffer
  local buf = vim.api.nvim_create_buf(true, true)
  local win
  if not no_init then
    local current_buffer = vim.call("getbufinfo", vim.call("bufnr"))[1]
    if current_buffer.linecount == 1 and current_buffer.changed == 0 and vim.call("getline", 1) == "" then
      win = vim.api.nvim_get_current_win()
    else
      vim.cmd("split")
      win = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_set_option("laststatus", 0)
  else
    vim.cmd("tabnew")
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(win, buf)

  local reply_buf = vim.api.nvim_create_buf(true, true)
  vim.cmd("below sb " .. tostring(buf))
  vim.cmd("resize 2")
  local reply_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(reply_win, reply_buf)

  -- set options for new buffer/window
  vim.api.nvim_buf_set_var(buf, "discord_content", {})
  vim.api.nvim_buf_set_var(buf, "vimcord_reply_buffer", reply_buf)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "discord_messages")

  -- ditto for the reply window
  vim.api.nvim_buf_set_var(reply_buf, "vimcord_target_buffer", buf)
  vim.api.nvim_buf_set_option(reply_buf, "filetype", "discord_reply")

  -- return to the buffer above
  vim.cmd("wincmd k")

  return buf
end

function vimcord.append_to_buffer(buffer, discord_message, reply, discord_extra)
  local window = vim.call("bufwinid", buffer)
  local bufindentopt = vim.api.nvim_win_get_option(window, "breakindentopt")
  local split_width = tonumber(
    vim.split(vim.split(bufindentopt, "shift:")[2] or "", ",")[1]
  ) or 0

  vim.api.nvim_buf_call(buffer, function()
    vim.call("vimcord#buffer#append", split_width, discord_message, reply, discord_extra)
  end)

  vim.api.nvim_win_call(window, function()
    vim.call("vimcord#scroll_cursor", #discord_message)
  end)
end

function vimcord.append_many_to_buffer(buffer, discord_messages)
  local window = vim.call("bufwinid", buffer)
  local bufindentopt = vim.api.nvim_win_get_option(window, "breakindentopt")
  local split_width = tonumber(
    vim.split(vim.split(bufindentopt, "shift:")[2] or "", ",")[1]
  ) or 0

  local line_count = -1
  vim.api.nvim_buf_call(buffer, function()
    for _, message in pairs(discord_messages) do
      local contents = message["contents"]
      local reply = message["reply"] or {}
      local discord_extra = message["extra"]
      vim.call("vimcord#buffer#append", split_width, contents, reply, discord_extra)
      line_count = line_count + #contents
    end
  end)

  vim.api.nvim_win_call(window, function()
    vim.call("vimcord#scroll_cursor", line_count)
  end)
end

function vimcord.edit_buffer_message(buffer, discord_message, as_reply, discord_extra)
  local window = vim.call("bufwinid", buffer)
  local bufindentopt = vim.api.nvim_win_get_option(window, "breakindentopt")
  local split_width = tonumber(
    vim.split(vim.split(bufindentopt, "shift:")[2] or "", ",")[1]
  ) or 0

  local added_lines = vim.api.nvim_buf_call(buffer, function()
    return vim.call("vimcord#buffer#edit", split_width, discord_message, as_reply, discord_extra)
  end)

  vim.api.nvim_win_call(window, function()
    vim.call("vimcord#scroll_cursor", added_lines)
  end)
end

function vimcord.delete_buffer_message(buffer, discord_message_id)
  vim.api.nvim_buf_call(buffer, function()
    vim.call("vimcord#buffer#delete", discord_message_id)
  end)
end

function vimcord.recolor_visited_links(buffer, unvisited)
  vim.api.nvim_buf_set_option(buffer, "modifiable", true)

  --fetch the cursor
  local window = vim.call("bufwinid", buffer)
  local cursor = vim.call("getcurpos", window)

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
  vim.call("setpos", ".", cursor)

  vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end
