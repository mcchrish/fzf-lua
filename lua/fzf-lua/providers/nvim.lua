if not pcall(require, "fzf") then
  return
end

local action = require("fzf.actions").action
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

M.commands = function(opts)

  opts = config.normalize_opts(opts, config.globals.nvim.commands)
  if not opts then return end

  coroutine.wrap(function ()

    local commands = vim.api.nvim_get_commands {}

    local prev_act = action(function (args)
      local cmd = args[1]
      if commands[cmd] then
        cmd = vim.inspect(commands[cmd])
      end
      return cmd
    end)

    local entries = {}
    for k, _ in pairs(commands) do
      table.insert(entries, utils.ansi_codes.magenta(k))
    end

    table.sort(entries, function(a, b) return a<b end)

    opts.nomulti = true
    opts.preview = prev_act

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()

end

local history = function(opts, str)
  coroutine.wrap(function ()

    local history = vim.fn.execute("history " .. str)
    history = vim.split(history, "\n")

    local entries = {}
    for i = #history, 3, -1 do
      local item = history[i]
      local _, finish = string.find(item, "%d+ +")
      table.insert(entries, string.sub(item, finish + 1))
    end

    opts.nomulti = true
    opts.preview = nil
    opts.preview_window = 'hidden:down:0'

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()
end

local arg_header = function(sel_key, edit_key, text)
  sel_key = utils.ansi_codes.yellow(sel_key)
  edit_key = utils.ansi_codes.yellow(edit_key)
  return ('--header=":: %s to %s, %s to edit"'):format(sel_key, text, edit_key)
end

M.command_history = function(opts)
  opts = config.normalize_opts(opts, config.globals.nvim.command_history)
  if not opts then return end
  opts._fzf_cli_args = arg_header("<CR>", "<Ctrl-e>", "execute")
  history(opts, "cmd")
end

M.search_history = function(opts)
  opts = config.normalize_opts(opts, config.globals.nvim.search_history)
  if not opts then return end
  opts._fzf_cli_args = arg_header("<CR>", "<Ctrl-e>", "search")
  history(opts, "search")
end

M.marks = function(opts)
  opts = config.normalize_opts(opts, config.globals.nvim.marks)
  if not opts then return end

  coroutine.wrap(function ()

    local marks = vim.fn.execute("marks")
    marks = vim.split(marks, "\n")

    local prev_act = action(function (args, fzf_lines, _)
      local mark = args[1]:match("[^ ]+")
      local bufnr, lnum, _, _ = unpack(vim.fn.getpos("'"..mark))
      if vim.api.nvim_buf_is_loaded(bufnr) then
        return vim.api.nvim_buf_get_lines(bufnr, lnum, fzf_lines+lnum, false)
      else
        local name = vim.fn.expand(args[1]:match(".* (.*)"))
        if vim.fn.filereadable(name) ~= 0 then
          return vim.fn.readfile(name, "", fzf_lines)
        end
        return "UNLOADED: " .. name
      end
    end)

    local entries = {}
    for i = #marks, 3, -1 do
      local mark, line, col, text = marks[i]:match("(.)%s+(%d+)%s+(%d+)%s+(.*)")
      table.insert(entries, string.format("%-15s %-15s %-15s %s",
        utils.ansi_codes.yellow(mark),
        utils.ansi_codes.blue(line),
        utils.ansi_codes.green(col),
        text))
    end

    table.sort(entries, function(a, b) return a<b end)

    opts.nomulti = true
    opts.preview = prev_act
    -- opts.preview_window = 'hidden:down:0'

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()
end

M.registers = function(opts)

  opts = config.normalize_opts(opts, config.globals.nvim.registers)
  if not opts then return end

  coroutine.wrap(function ()

    local registers = { '"', "_", "#", "=", "_", "/", "*", "+", ":", ".", "%" }
    -- named
    for i = 0, 9 do
      table.insert(registers, tostring(i))
    end
    -- alphabetical
    for i = 65, 90 do
      table.insert(registers, string.char(i))
    end

    local prev_act = action(function (args)
      local r = args[1]:match("%[(.*)%] ")
      local _, contents = pcall(vim.fn.getreg, r)
      return contents or args[1]
    end)

    local entries = {}
    for _, r in ipairs(registers) do
      -- pcall as this could fail with:
      -- E5108: Error executing lua Vim:clipboard:
      --        provider returned invalid data
      local _, contents = pcall(vim.fn.getreg, r)
      contents = contents:gsub("\n", utils.ansi_codes.magenta("\\n"))
      if (contents and #contents > 0) or not opts.ignore_empty then
        table.insert(entries, string.format("[%s] %s",
          utils.ansi_codes.yellow(r), contents))
      end
    end

    opts.nomulti = true
    opts.preview = prev_act

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()
end

M.keymaps = function(opts)

  opts = config.normalize_opts(opts, config.globals.nvim.keymaps)
  if not opts then return end

  coroutine.wrap(function ()

    local modes = { "n", "i", "c" }
    local keymaps = {}

    local add_keymap = function(keymap)
      -- hijack field
      keymap.str = string.format("[%s:%s:%s]",
        utils.ansi_codes.yellow(tostring(keymap.buffer)),
        utils.ansi_codes.green(keymap.mode),
        utils.ansi_codes.magenta(keymap.lhs))
      local k = string.format("[%s:%s:%s]",
        keymap.buffer, keymap.mode, keymap.lhs)
      keymaps[k] = keymap
    end

    for _, mode in pairs(modes) do
      local global = vim.api.nvim_get_keymap(mode)
      for _, keymap in pairs(global) do
        add_keymap(keymap)
      end
      local buf_local = vim.api.nvim_buf_get_keymap(0, mode)
      for _, keymap in pairs(buf_local) do
        add_keymap(keymap)
      end
    end

    local prev_act = action(function (args)
      local k = args[1]:match("(%[.*%]) ")
      local v = keymaps[k]
      if v then
        -- clear hijacked field
        v.str = nil
        k = vim.inspect(v)
      end
      return k
    end)

    local entries = {}
    for _, v in pairs(keymaps) do
      table.insert(entries, string.format("%-50s %s",
      v.str, v.rhs))
    end

    opts.nomulti = true
    opts.preview = prev_act

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()
end

M.spell_suggest = function(opts)

  -- if not vim.wo.spell then return false end
  opts = config.normalize_opts(opts, config.globals.nvim.spell_suggest)
  if not opts then return end

  coroutine.wrap(function ()

    local cursor_word = vim.fn.expand "<cword>"
    local entries = vim.fn.spellsuggest(cursor_word)

    if vim.tbl_isempty(entries) then return end

    opts.nomulti = true
    opts.preview = nil
    opts.preview_window = 'hidden:down:0'

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()

end

M.filetypes = function(opts)

  opts = config.normalize_opts(opts, config.globals.nvim.filetypes)
  if not opts then return end

  coroutine.wrap(function ()

    local entries = vim.fn.getcompletion('', 'filetype')
    if vim.tbl_isempty(entries) then return end

    opts.nomulti = true
    opts.preview = nil
    opts.preview_window = 'hidden:down:0'

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()

end

M.packadd = function(opts)

  opts = config.normalize_opts(opts, config.globals.nvim.packadd)
  if not opts then return end

  coroutine.wrap(function ()

    local entries = vim.fn.getcompletion('', 'packadd')

    if vim.tbl_isempty(entries) then return end

    opts.nomulti = false
    opts.preview = nil
    opts.preview_window = 'hidden:down:0'

    local selected = core.fzf(opts, entries)

    if not selected then return end
    actions.act(opts.actions, selected)

  end)()

end

return M
