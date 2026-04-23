local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__eqInt32(a, b) if a == b then return {0} else return {1} end end

function M.v_render(v_b)
  return (function(s) if s[1] == 0 then return "T" elseif s[1] == 1 then return "F" end end)(v_b)
end

M.v_minInt32 = -2147483648

function M.main(v__input)
  return M.__print(table.concat({(M.v_render)(M.__eqInt32(42, 42)), (M.v_render)(M.__eqInt32(42, 7)), (M.v_render)(M.__eqInt32(M.v_minInt32, M.v_minInt32)), (M.v_render)(M.__eqInt32(0, 1))}))
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
