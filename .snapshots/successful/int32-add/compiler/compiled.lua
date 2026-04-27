local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__addInt32(a, b) local s = a + b if s > 2147483647 then return {0, {1}} elseif s < -2147483648 then return {0, {0}} else return {1, s} end end

function M.v_showArithError(v_e)
  return (function(s) if s[1] == 0 then return "Underflow" elseif s[1] == 1 then return "Overflow" end end)(v_e)
end

function M.v_render(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("err: " .. (M.v_showArithError)(v_e)) elseif s[1] == 1 then local v_v = s[2]; return ("ok: " .. tostring(v_v)) end end)(v_r)
end

M.v_maxInt32 = 2147483647

M.v_minInt32 = -2147483648

function M.main(v__input)
  return M.__print(table.concat({(M.v_render)(M.__addInt32(100, 23)), ", ", (M.v_render)(M.__addInt32(100, -50)), ", ", (M.v_render)(M.__addInt32(M.v_maxInt32, 1)), ", ", (M.v_render)(M.__addInt32(M.v_minInt32, -1)), ", ", (M.v_render)(M.__addInt32(M.v_maxInt32, M.v_minInt32))}))
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
