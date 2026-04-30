local M = {}

local augroup_name = "termyank"
local fallback_registers = { '"', "-", "1", "*", "+" }

local function strip_cr_lines(lines)
  local changed = false
  local out = {}
  for i, line in ipairs(lines) do
    local new_line, n = line:gsub("\r", "")
    if n > 0 then
      changed = true
    end
    out[i] = new_line
  end
  return out, changed
end

local function is_blockwise(regtype)
  return regtype and regtype:sub(1, 1) == "\22"
end

local function transform_for_regtype(lines, regtype)
  if is_blockwise(regtype) then
    return nil
  end
  local stripped, changed = strip_cr_lines(lines)
  if #lines == 1 and not changed then
    return nil
  end
  return { table.concat(stripped, "") }, "v"
end

local function sanitize_register(regname, lines, regtype)
  if not lines or #lines == 0 then
    return
  end
  local cleaned, new_regtype = transform_for_regtype(lines, regtype)
  if not cleaned then
    return
  end
  local target = (regname == nil or regname == "") and '"' or regname
  vim.fn.setreg(target, cleaned, new_regtype)
end

local function sanitize_register_by_name(regname)
  local info = vim.fn.getreginfo(regname)
  if not info or not info.regcontents then
    return
  end
  sanitize_register(regname, info.regcontents, info.regtype)
end

local function on_text_yank_post()
  if vim.bo.buftype ~= "terminal" then
    return
  end
  local event = vim.v.event
  sanitize_register(event.regname, event.regcontents, event.regtype)
end

local function on_text_changed()
  local seen = {}
  local function visit(name)
    if not name or name == "" or seen[name] then
      return
    end
    seen[name] = true
    sanitize_register_by_name(name)
  end
  for _, name in ipairs(fallback_registers) do
    visit(name)
  end
  visit(vim.v.register)
end

function M._sanitize_register(regname, lines, regtype)
  sanitize_register(regname, lines, regtype)
end

function M.setup(_)
  if vim.g.loaded_termyank_setup then
    return
  end
  vim.g.loaded_termyank_setup = true

  local group = vim.api.nvim_create_augroup(augroup_name, { clear = true })

  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = on_text_yank_post,
  })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(args)
      vim.api.nvim_create_autocmd("TextChanged", {
        group = group,
        buffer = args.buf,
        callback = on_text_changed,
      })
    end,
  })
end

return M
