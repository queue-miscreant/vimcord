if vimcord == nil then vimcord = {} end

LINKS_NAMESPACE = vim.api.nvim_create_namespace("vimcord-links")

function vimcord.init()
  local old_window = vim.api.nvim_get_current_win()
  -- parse input
  local buf_lines = {}
  local content = {}
  -- for i = 1, #input do
  --   local text = input[i][1]
  --   local value = input[i][2]
  --   if type(text) ~= "string" or value == nil then
  --     error("Table value is not of form {string, value}")
  --   end
  --   table.insert(buf_lines, text)
  --   table.insert(content, value)
  -- end

  -- open split to an empty scratch
  vim.cmd("new")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_win_set_buf(win, buf)

  -- set buffer content
  -- vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
  -- vim.api.nvim_buf_set_var(buf, "selection", content)

  -- set options for new buffer/window
  vim.api.nvim_buf_set_var(buf, "discord_content", {})
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "discord_messages")

  return buf
end

function vimcord.append_to_buffer(buffer, discord_message, discord_extra)
  local window = vim.call("bufwinid", buffer)

  status, result = pcall(function()
    vim.api.nvim_buf_call(buffer, function()
      vim.api.nvim_buf_set_option(buffer, "modifiable", true)
      local line_number = #vim.b["discord_content"]
      local new_extra = #discord_message 
      vim.call(
        "setbufline",
        buffer,
        line_number + 1,
        vim.tbl_map(function(v) return " " .. v end, discord_message)
      )
      vim.call("vimcord#add_discord_data", discord_extra, new_extra)

      vim.api.nvim_buf_set_option(buffer, "modifiable", false)
    end)

    vim.api.nvim_win_call(window, function()
      vim.call("vimcord#scroll_cursor", #discord_message)
    end)
  end)
  vim.print(tostring(status) .. " " .. tostring(result))
end

-- TODO: these can be raw vimscript functions
-- TODO: remove extmarks
function vimcord.edit_buffer_message(buffer, discord_message, discord_extra)
  local window = vim.call("bufwinid", buffer)

  status, result = pcall(function()
    vim.api.nvim_buf_call(buffer, function()
      vim.api.nvim_buf_set_option(buffer, "modifiable", true)

      old_lines = {}
      start_line = math.huge
      end_line = 0
      for i, data in pairs(vim.b["discord_content"]) do
        if data.message_id == discord_extra.message_id then
          table.insert(old_lines, {i, data})
          start_line = math.min(start_line, i)
          end_line = math.max(end_line, i)
        end
      end
      if start_line == math.huge then return end

      if start_line + 1 <= end_line then
        vim.call(
          "deletebufline",
          buffer,
          start_line + 1,
          end_line
        )
      end
      vim.call(
        "setbufline",
        buffer,
        start_line,
        vim.tbl_map(function(v) return " " .. v end, discord_message)
      )
      vim.call("vimcord#insert_discord_data", discord_extra, #discord_message, start_line, end_line)

      vim.api.nvim_buf_set_option(buffer, "modifiable", false)
    end)
  end)
  vim.print(tostring(status) .. " " .. tostring(result))
end

-- TODO: these can be raw vimscript functions
-- TODO: remove extmarks
function vimcord.delete_buffer_message(buffer, discord_message_id)
  local window = vim.call("bufwinid", buffer)

  status, result = pcall(function()
    vim.api.nvim_buf_call(buffer, function()
      vim.api.nvim_buf_set_option(buffer, "modifiable", true)

      old_lines = {}
      start_line = math.huge
      end_line = 0
      for i, data in pairs(vim.b["discord_content"]) do
        if data.message_id == discord_message_id then
          table.insert(old_lines, {i, data})
          start_line = math.min(start_line, i)
          end_line = math.max(end_line, i)
        end
      end
      if start_line == math.huge then return end

      vim.call(
        "deletebufline",
        buffer,
        start_line,
        end_line
      )
      vim.call("vimcord#delete_discord_data", start_line, end_line)

      vim.api.nvim_buf_set_option(buffer, "modifiable", false)
    end)
  end)
  vim.print(tostring(status) .. " " .. tostring(result))
end

function vimcord.recolor_visited_links(buffer, unvisited)
  vim.api.nvim_buf_set_option(buffer, "modifiable", true)
  local visited_color = vim.g["vimcord_visited_link_color"]

  -- even in vimscript, this would be an execute command, so I'm not torn up about it being here
  for _, j in pairs(unvisited) do
    local escape_slashes = j:gsub("/", "\\/")
    pcall(function()
      vim.cmd(
        "%sno/\\(\\%x1B\\)100 \\(" .. escape_slashes ..
        "\\%x1B\\)/\\1" .. visited_color .. " \\2/g"
      )
    end)
  end

  vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end

function vimcord.add_link_extmarks(buffer, message_id, opengl_data)
  vim.api.nvim_buf_set_option(buffer, "modifiable", true)

  local line_number = vim.api.nvim_buf_call(buffer, function()
    local content = vim.b["discord_content"]
    for i = #content, 1, -1 do
      if content[i]["message_id"] == message_id then
        return i
      end
    end
    return 0
  end)

  if line_number == 0 then
    vim.api.nvim_notify("Could not find message with id " .. tostring(message_id) .. "!", 4, {})
    return
  end

  vim.api.nvim_buf_set_extmark(
    buffer,
    LINKS_NAMESPACE,
    line_number - 1,
    0,
    {
      virt_lines=opengl_data
    }
  )

  vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end
