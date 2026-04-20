local function __print(s) io.write(tostring(s)); return nil end

function main(v__input)
  return __print(table.concat({tostring(v_minInt32), ", ", tostring(v_negative), ", ", tostring(v_zero), ", ", tostring(v_positive), ", ", tostring(v_manyDigits), ", ", tostring(v_maxInt32)}))
end

v_minInt32 = -2147483648

v_negative = -42

v_zero = 0

v_positive = 7

v_manyDigits = 1234567

v_maxInt32 = 2147483647

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
  if type(main) == 'function' then main(input) end
end
