local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.main(v__input)
  return M.__print(table.concat({tostring(M.v_minInt32), ", ", tostring(M.v_negative), ", ", tostring(M.v_zero), ", ", tostring(M.v_positive), ", ", tostring(M.v_manyDigits), ", ", tostring(M.v_maxInt32)}))
end

M.v_minInt32 = -2147483648

M.v_negative = -42

M.v_zero = 0

M.v_positive = 7

M.v_manyDigits = 1234567

M.v_maxInt32 = 2147483647

local ok, dbg = pcall(require, 'debug')
local should_run = false
if ok and dbg and dbg.getinfo then
  local info = dbg.getinfo(1, 'S')
  should_run = info and info.what == 'main'
else
  should_run = true
end
if should_run then
  local input = (_G and _G.arg and _G.arg[1]) or ""
  if type(M.main) == 'function' then M.main(input) end
end
