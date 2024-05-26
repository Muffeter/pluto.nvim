local Term = {}
local M = {}
local defaults = {
  ft = 'FTerm',
  cmd = function()
    return assert(
      os.getenv('SHELL'),
      '[FTerm] $SHELL is not present! Please provide a shell (`config.cmd`) to use.'
    )
  end,
  border = 'single',
  auto_close = true,
  hl = 'Normal',
  blend = 0,
  clear_env = false,
  dimensions = {
    height = 0.8,
    width = 0.8,
    x = 0.5,
    y = 0.5,
  },
  task = {
    command = "gcc",
    args = {},
    output = nil
  }
}

function Term:new()
  return setmetatable({
    win = nil,
    buf = nil,
    terminal = nil,
    config = defaults,
  }, { __index = self })
end

function Term:setup(cfg)
  if not cfg then
    return
  end

  self.config = vim.tbl_deep_extend('force', self.config, cfg)

  return self
end

function is_win_valid(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function is_buf_valid(buf)
  return buf and vim.api.nvim_buf_is_loaded(buf)
end

function is_cmd(cmd)
  return type(cmd) == 'function' and cmd() or cmd
end

function get_dimension(opts)
  -- get lines and columns
  local cl = vim.o.columns
  local ln = vim.o.lines

  -- calculate our floating window size
  local width = math.ceil(cl * opts.width)
  local height = math.ceil(ln * opts.height - 4)

  -- and its starting position
  local col = math.ceil((cl - width) * opts.x)
  local row = math.ceil((ln - height) * opts.y - 1)

  return {
    width = width,
    height = height,
    col = col,
    row = row,
  }
end

function Term:create_buf()
  -- If previous buffer exists then return it
  local prev = self.buf

  if is_buf_valid(prev) then
    return prev
  end

  local buf = vim.api.nvim_create_buf(false, true)

  -- this ensures filetype is set to Fterm on first run
  vim.api.nvim_buf_set_option(buf, 'filetype', self.config.ft)

  return buf
end

function Term:create_win(buf)
  local cfg = self.config

  local dim = get_dimension(cfg.dimensions)

  local win = vim.api.nvim_open_win(buf, true, {
    border = cfg.border,
    relative = 'editor',
    style = 'minimal',
    width = dim.width,
    height = dim.height,
    col = dim.col,
    row = dim.row,
  })

  vim.api.nvim_win_set_option(win, 'winhl', ('Normal:%s'):format(cfg.hl))
  vim.api.nvim_win_set_option(win, 'winblend', cfg.blend)

  return win
end

function Term:open(cmd)
  -- Move to existing window if the window already exists
  if is_win_valid(self.win) then
    return vim.api.nvim_set_current_win(self.win)
  end

  -- self:remember_cursor()

  -- Create new window and terminal if it doesn't exist
  local buf = self:create_buf()
  local win = self:create_win(buf)

  -- This means we are just toggling the terminal
  -- So we don't have to call `:open_term()`
  if self.buf == buf then
    return self:store(win, buf):prompt()
  end

  return self:store(win, buf):open_term(cmd)
end

function Term:store(win, buf)
  self.win = win
  self.buf = buf

  return self
end

function Term:close(force)
  if not is_win_valid(self.win) then
    return self
  end

  vim.api.nvim_win_close(self.win, {})

  self.win = nil

  if force then
    if is_buf_valid(self.buf) then
      vim.api.nvim_buf_delete(self.buf, { force = true })
    end

    vim.fn.jobstop(self.terminal)

    self.buf = nil
    self.terminal = nil
  end

  return self
end

function Term:open_term(cmd)
  -- NOTE: `termopen` will fails if the current buffer is modified
  self.terminal = vim.fn.termopen(is_cmd(self.config.cmd), {
    clear_env = self.config.clear_env,
    env = self.config.env,
    on_stdout = self.config.on_stdout,
    on_stderr = self.config.on_stderr,
    on_exit = function(...)
      self:handle_exit(...)
    end,
  })
  -- This prevents the filetype being changed to `term` instead of `FTerm` when closing the floating window
  vim.api.nvim_buf_set_option(self.buf, 'filetype', self.config.ft)

  return self:prompt()
end

function Term:prompt()
  -- vim.api.nvim_command('startinsert')
  local map = vim.keymap.set
  map('n', 'q', function()
      self:close()
    end,
    { buffer = self.buf })
  return self
end

function Term:run(command)
  self:open()

  local exec = is_cmd(command)

  vim.api.nvim_chan_send(
    self.terminal,
    table.concat({
      type(exec) == 'table' and table.concat(exec, ' ') or exec,
      vim.api.nvim_replace_termcodes('<CR>', true, true, true),
    })
  )

  return self
end

local function pathJoin(path)
  local result = ""
  for i = 1, #path do
    result = result .. path[i] .. " "
  end
  return result
end

local t = Term:new()

M.cmpi = function()
  local task = t.config.task

  local current_file = vim.fn.expand('%')
  -- ignore relative path dot
  local sep = string.find(current_file, ".", 2, true)
  local output = string.sub(current_file, 1, sep - 1)

  if task.output then
    output = task.output
  end
  local command = pathJoin({task.command, current_file, "-o", "./" .. output})
  t:open()
  t:run(command)
  local runCmd = pathJoin({"./" .. output})
  t:run(runCmd)
end

M.setup = function(cfg)
  t:setup(cfg)
  vim.api.nvim_create_user_command("Cmpi", M.cmpi, {})
end

return M
