local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__predUInt8(x) if x == 0 then return {0, {0}} else return {1, x - 1} end end

function M.v_countDown(v_n)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; return tostring(v_n) elseif s[1] == 1 then local v_m = s[2]; return table.concat({tostring(v_n), ",", (M.v_countDown)(v_m)}) end end)(M.__predUInt8(v_n))
end

function M.main(v__input)
  return M.__print((M.v_countDown)(255))
end

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
