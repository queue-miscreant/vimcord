-- discord.lua
--
-- Actual functions which call into the common ones in buffer.lua. They interact with Discord data
-- and use autoloaded functions in vimcord/discord

buffer = require"vimcord/buffer"

local function create_window(...)
  create_tab, buf = ...
  if buf ~= nil then
    buf = vim.g.vimcord.discord_message_buffer
  end

  local buffer_number = buffer.create_window(create_tab, buf)
  -- hold off until we've got a window to set the filetype
  vim.api.nvim_buf_set_option(buffer_number, "filetype", "discord_messages")
  -- set this as the discord buffer
  vim.cmd("let g:vimcord['discord_message_buffer'] = " .. tostring(buffer_number))
end

local function wrap_discord(func, fetch_discord_id)
  return function(...)
    local status, buffer = pcall(function() return vim.g.vimcord.discord_message_buffer end)
    if not status then
      error("Could not call Discord function -- no buffer exists!")
    end

    args = {...}
    --modify the first argument to use message_id instead of discord_message_id
    if fetch_discord_id ~= nil then
      discord_message_id = args[1]
      local message_number = vim.call("vimcord#discord#local#get_message_number", discord_message_id)
      if message_number < 0 then return 0 end

      args[1] = message_number
    end

    -- Run the function inside the buffer (so that line() works properly)
    vim.api.nvim_buf_call(buffer, function() func(unpack(args)) end)
  end
end

-- Also change reply extmarks
local function edit_buffer_message(message_number, as_reply, ...)
  buffer.edit_buffer_message(message_number, ...)
  vim.call("vimcord#discord#local#redo_reply_extmarks", message_number, as_reply)
end

-- Also delete reply extmarks
local function delete_buffer_message(message_number)
  buffer.delete_buffer_message(message_number)
  vim.call(
    "vimcord#discord#local#redo_reply_extmarks",
    message_number,
    {{"(Deleted)", "discordReply"}}
  )
end

discord = {
  create_window=create_window,
  append_messages_to_buffer=wrap_discord(buffer.append_messages_to_buffer),
  edit_buffer_message=wrap_discord(edit_buffer_message, true),
  delete_buffer_message=wrap_discord(delete_buffer_message, true),
  add_link_extmarks=wrap_discord(buffer.add_link_extmarks, true),
}

return discord
