local M = {}

local augroup_name = "termyank"
local fallback_registers = { '"', "-", "1", "*", "+" }
local enabled = true

local default_opts = {
  text_objects_span_lines = true,
}
local opts = default_opts

local wrap_aware_text_objects = {
  "iW", "aW",
  'i"', 'a"', "i'", "a'", "i`", "a`",
  "i(", "a(", "i)", "a)", "ib", "ab",
  "i[", "a[", "i]", "a]",
  "i{", "a{", "i}", "a}", "iB", "aB",
}

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
  if not enabled or vim.bo.buftype ~= "terminal" then
    return
  end
  local event = vim.v.event
  sanitize_register(event.regname, event.regcontents, event.regtype)
end

local function on_text_changed()
  if not enabled then
    return
  end
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

local function line_is_blank(buf, lnum)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if not line then
    return true
  end
  return line:match("^%s*$") ~= nil
end

local function char_at(buf, lnum, col)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if not line or col < 1 or col > #line then
    return nil
  end
  return line:sub(col, col)
end

local function is_nonwhite(c)
  return c ~= nil and c:match("%S") ~= nil
end

local function find_extended_WORD(buf, lnum, col)
  if not is_nonwhite(char_at(buf, lnum, col)) then
    return nil
  end

  local start_lnum, start_col = lnum, col
  while true do
    if start_col > 1 and is_nonwhite(char_at(buf, start_lnum, start_col - 1)) then
      start_col = start_col - 1
    elseif start_col == 1 and start_lnum > 1 and not line_is_blank(buf, start_lnum - 1) then
      local prev = vim.api.nvim_buf_get_lines(buf, start_lnum - 2, start_lnum - 1, false)[1]
      if prev and #prev > 0 and is_nonwhite(prev:sub(#prev, #prev)) then
        start_lnum = start_lnum - 1
        start_col = #prev
      else
        break
      end
    else
      break
    end
  end

  local end_lnum, end_col = lnum, col
  local last_line = vim.api.nvim_buf_line_count(buf)
  while true do
    local cur = vim.api.nvim_buf_get_lines(buf, end_lnum - 1, end_lnum, false)[1] or ""
    if end_col < #cur and is_nonwhite(cur:sub(end_col + 1, end_col + 1)) then
      end_col = end_col + 1
    elseif end_col == #cur and end_lnum < last_line and not line_is_blank(buf, end_lnum + 1) then
      local nxt = vim.api.nvim_buf_get_lines(buf, end_lnum, end_lnum + 1, false)[1] or ""
      if #nxt > 0 and is_nonwhite(nxt:sub(1, 1)) then
        end_lnum = end_lnum + 1
        end_col = 1
      else
        break
      end
    else
      break
    end
  end

  return start_lnum, start_col, end_lnum, end_col
end

local function select_extended_WORD(inclusive_trailing_ws)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(win)
  local lnum, col = pos[1], pos[2] + 1

  local s_l, s_c, e_l, e_c = find_extended_WORD(buf, lnum, col)
  if not s_l then
    return
  end

  if inclusive_trailing_ws then
    local last_line = vim.api.nvim_buf_line_count(buf)
    local cur = vim.api.nvim_buf_get_lines(buf, e_l - 1, e_l, false)[1] or ""
    while e_c < #cur and cur:sub(e_c + 1, e_c + 1):match("%s") do
      e_c = e_c + 1
    end
    if e_c == #cur and e_l < last_line and line_is_blank(buf, e_l + 1) then
      -- leave at end of line; don't span into blank lines
    end
  end

  vim.api.nvim_win_set_cursor(win, { s_l, s_c - 1 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(win, { e_l, e_c - 1 })
end

function M._select_iW()
  select_extended_WORD(false)
end

function M._select_aW()
  select_extended_WORD(true)
end

local function step_forward(buf, lnum, col)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  if not line then
    return nil
  end
  if col < #line then
    return lnum, col + 1
  end
  local last_line = vim.api.nvim_buf_line_count(buf)
  if lnum >= last_line or line_is_blank(buf, lnum + 1) then
    return nil
  end
  return lnum + 1, 1
end

local function step_backward(buf, lnum, col)
  if col > 1 then
    return lnum, col - 1
  end
  if lnum <= 1 or line_is_blank(buf, lnum - 1) then
    return nil
  end
  local prev = vim.api.nvim_buf_get_lines(buf, lnum - 2, lnum - 1, false)[1] or ""
  if #prev == 0 then
    return nil
  end
  return lnum - 1, #prev
end

local function find_pair_nested(buf, lnum, col, open_ch, close_ch)
  local s_l, s_c
  local depth = 1
  local l, c = step_backward(buf, lnum, col)
  while l do
    local ch = char_at(buf, l, c)
    if ch == close_ch then
      depth = depth + 1
    elseif ch == open_ch then
      depth = depth - 1
      if depth == 0 then
        s_l, s_c = l, c
        break
      end
    end
    l, c = step_backward(buf, l, c)
  end
  if not s_l then
    return nil
  end

  local e_l, e_c
  depth = 1
  l, c = step_forward(buf, lnum, col)
  while l do
    local ch = char_at(buf, l, c)
    if ch == open_ch then
      depth = depth + 1
    elseif ch == close_ch then
      depth = depth - 1
      if depth == 0 then
        e_l, e_c = l, c
        break
      end
    end
    l, c = step_forward(buf, l, c)
  end
  if not e_l then
    return nil
  end

  return s_l, s_c, e_l, e_c
end

local function find_pair_quote(buf, lnum, col, quote_ch)
  if char_at(buf, lnum, col) == quote_ch then
    -- Ambiguous position: treat as opening quote and search forward for close.
    local fl, fc = step_forward(buf, lnum, col)
    while fl do
      if char_at(buf, fl, fc) == quote_ch then
        return lnum, col, fl, fc
      end
      fl, fc = step_forward(buf, fl, fc)
    end
    return nil
  end

  local s_l, s_c
  local l, c = step_backward(buf, lnum, col)
  while l do
    if char_at(buf, l, c) == quote_ch then
      s_l, s_c = l, c
      break
    end
    l, c = step_backward(buf, l, c)
  end
  if not s_l then
    return nil
  end

  local e_l, e_c
  l, c = step_forward(buf, lnum, col)
  while l do
    if char_at(buf, l, c) == quote_ch then
      e_l, e_c = l, c
      break
    end
    l, c = step_forward(buf, l, c)
  end
  if not e_l then
    return nil
  end

  return s_l, s_c, e_l, e_c
end

local function select_range_inside(s_l, s_c, e_l, e_c)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local i_s_l, i_s_c = step_forward(buf, s_l, s_c)
  local i_e_l, i_e_c = step_backward(buf, e_l, e_c)
  if not i_s_l or not i_e_l then
    return
  end
  if i_s_l > i_e_l or (i_s_l == i_e_l and i_s_c > i_e_c) then
    return
  end
  vim.api.nvim_win_set_cursor(win, { i_s_l, i_s_c - 1 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(win, { i_e_l, i_e_c - 1 })
end

local function select_range_around(s_l, s_c, e_l, e_c)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(win, { s_l, s_c - 1 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(win, { e_l, e_c - 1 })
end

local bracket_pairs = {
  ["("] = { open = "(", close = ")" },
  [")"] = { open = "(", close = ")" },
  ["b"] = { open = "(", close = ")" },
  ["["] = { open = "[", close = "]" },
  ["]"] = { open = "[", close = "]" },
  ["{"] = { open = "{", close = "}" },
  ["}"] = { open = "{", close = "}" },
  ["B"] = { open = "{", close = "}" },
}

local quote_chars = { ['"'] = true, ["'"] = true, ["`"] = true }

local function select_pair(key, inclusive)
  local buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1], pos[2] + 1

  local s_l, s_c, e_l, e_c
  local pair = bracket_pairs[key]
  if pair then
    s_l, s_c, e_l, e_c = find_pair_nested(buf, lnum, col, pair.open, pair.close)
  elseif quote_chars[key] then
    s_l, s_c, e_l, e_c = find_pair_quote(buf, lnum, col, key)
  end
  if not s_l then
    return
  end

  if inclusive then
    select_range_around(s_l, s_c, e_l, e_c)
  else
    select_range_inside(s_l, s_c, e_l, e_c)
  end
end

local pair_keys = { '"', "'", "`", "(", ")", "b", "[", "]", "{", "}", "B" }

for _, k in ipairs(pair_keys) do
  local key = k
  M["_select_i" .. key] = function()
    select_pair(key, false)
  end
  M["_select_a" .. key] = function()
    select_pair(key, true)
  end
end

local text_object_handlers = {
  iW = "_select_iW",
  aW = "_select_aW",
}
for _, k in ipairs(pair_keys) do
  text_object_handlers["i" .. k] = "_select_i" .. k
  text_object_handlers["a" .. k] = "_select_a" .. k
end

local function install_text_objects(buf)
  if not opts.text_objects_span_lines then
    return
  end
  for _, name in ipairs(wrap_aware_text_objects) do
    local handler = text_object_handlers[name]
    if handler then
      vim.keymap.set({ "o", "x" }, name, function()
        M[handler]()
      end, { buffer = buf, silent = true })
    end
  end
end

function M.enable()
  enabled = true
  vim.notify("termyank: on", vim.log.levels.INFO)
end

function M.disable()
  enabled = false
  vim.notify("termyank: off", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.is_enabled()
  return enabled
end

function M._sanitize_register(regname, lines, regtype)
  sanitize_register(regname, lines, regtype)
end

function M.setup(user_opts)
  if vim.g.loaded_termyank_setup then
    return
  end
  vim.g.loaded_termyank_setup = true

  opts = vim.tbl_deep_extend("force", default_opts, user_opts or {})

  local group = vim.api.nvim_create_augroup(augroup_name, { clear = true })

  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = on_text_yank_post,
  })

  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = function(args)
      vim.wo.wrap = true
      install_text_objects(args.buf)
      vim.api.nvim_create_autocmd("TextChanged", {
        group = group,
        buffer = args.buf,
        callback = on_text_changed,
      })
    end,
  })

  vim.api.nvim_create_user_command("TermYankOn", M.enable, {})
  vim.api.nvim_create_user_command("TermYankOff", M.disable, {})
  vim.api.nvim_create_user_command("TermYankToggle", M.toggle, {})
end

return M
