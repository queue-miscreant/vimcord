-- vimcord.lua
--
-- Utility functions that wrap Vimscript functions in `nvim_buf_call` and `nvim_win_call`s
-- In the future, this may be used for keeping track of buffer/channel mappings

if vimcord == nil then vimcord = {} end

local LINKS_NAMESPACE = vim.api.nvim_create_namespace("vimcord-links") -- for opengraph previews and visited link highlights
local REPLY_NAMESPACE = vim.api.nvim_create_namespace("vimcord-replies") -- for direct replies as virtual lines
local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace("vimcord-highlights") -- for "highlighted" messages, i.e., mentions
vimcord.LINKS_NAMESPACE = LINKS_NAMESPACE
vimcord.REPLY_NAMESPACE = REPLY_NAMESPACE
vimcord.HIGHLIGHT_NAMESPACE = HIGHLIGHT_NAMESPACE

vimcord.buffer = require"vimcord/buffer"
vimcord.discord = require"vimcord/discord"
