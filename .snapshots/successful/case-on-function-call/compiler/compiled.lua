local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_search(v_key)
  return {0, ("found:" .. v_key)}
end

function M.main(v__input)
  return M.__print((function(s) if s[1] == 0 then local v_v = s[2]; return v_v elseif s[1] == 1 then return "nothing" end end)((M.v_search)("hello")))
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
