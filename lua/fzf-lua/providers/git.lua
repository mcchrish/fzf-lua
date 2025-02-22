if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local path = require "fzf-lua.path"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"
local actions = require "fzf-lua.actions"

local M = {}

local function git_version()
  local out = vim.fn.system("git --version")
  return out:match("(%d+.%d+).")
end

M.files = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.files)
  if not opts then return end
  opts.cwd = path.git_root(opts.cwd)
  if not opts.cwd then return end
  local make_entry_file = core.make_entry_file
  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = opts.cmd, cwd = opts.cwd},
    function(x)
      return make_entry_file(opts, x)
    end)
  return core.fzf_files(opts)
end

M.status = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.status)
  if not opts then return end
  opts.cwd = path.git_root(opts.cwd)
  if not opts.cwd then return end
  if opts.preview then
    opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts.cwd))
  end
  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = opts.cmd, cwd = opts.cwd},
    function(x)
      -- greedy match anything after last space
      x = x:match("[^ ]*$")
      return core.make_entry_file(opts, x)
    end)
  return core.fzf_files(opts)
end

local function git_cmd(opts)
  opts.cwd = path.git_root(opts.cwd)
  if not opts.cwd then return end
  coroutine.wrap(function ()
    opts.fzf_fn = fzf_helpers.cmd_line_transformer(
      {cmd = opts.cmd, cwd = opts.cwd},
      function(x) return x end)
    local selected = core.fzf(opts, opts.fzf_fn)
    if not selected then return end
    actions.act(opts.actions, selected, opts)
  end)()
end

M.commits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.commits)
  if not opts then return end
  opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts.cwd))
  return git_cmd(opts)
end

M.bcommits = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.bcommits)
  if not opts then return end
  local git_root = path.git_root(opts.cwd)
  if not git_root then return end
  local file = path.relative(vim.fn.expand("%:p"), git_root)
  opts.cmd = opts.cmd .. " " .. file
  local git_ver = git_version()
  -- rotate-to first appeared with git version 2.31
  if git_ver and tonumber(git_ver) >= 2.31 then
    opts.preview = opts.preview .. " --rotate-to=" .. vim.fn.shellescape(file)
  end
  opts.preview = vim.fn.shellescape(path.git_cwd(opts.preview, opts.cwd))
  return git_cmd(opts)
end

M.branches = function(opts)
  opts = config.normalize_opts(opts, config.globals.git.branches)
  if not opts then return end
  opts.nomulti = true
  opts._preview = path.git_cwd(opts.preview, opts.cwd)
  opts.preview = fzf_helpers.choices_to_shell_cmd_previewer(function(items)
    local branch = items[1]:gsub("%*", "")  -- remove the * from current branch
    if branch:find("%)") ~= nil then
      -- (HEAD detached at origin/master)
      branch = branch:match(".* ([^%)]+)") or ""
    else
      -- remove anything past space
      branch = branch:match("[^ ]+")
    end
    return opts._preview:gsub("{.*}", branch)
    -- return "echo " .. branch
  end)
  return git_cmd(opts)
end

return M
