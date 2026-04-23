local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__succInt32(x) if x == 2147483647 then return {0, {0}} else return {1, x + 1} end end

function M.v_showOverflowError(v__wild0)
  return "OverflowError"
end

function M.v_render(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("overflow: " .. (M.v_showOverflowError)(v_e)) elseif s[1] == 1 then local v_v = s[2]; return ("ok: " .. tostring(v_v)) end end)(v_r)
end

M.v_maxInt32 = 2147483647

M.v_ordinary = 42

function M.main(v__input)
  return M.__print(table.concat({(M.v_render)(M.__succInt32(M.v_ordinary)), ", ", (M.v_render)(M.__succInt32(M.v_maxInt32))}))
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
