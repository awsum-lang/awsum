local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_show(v_u)
  return (function(s) if s[1] == 0 then return "Unit" end end)(v_u)
end

function M.main(v__input)
  return M.__print((M.v_show)({0}))
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
