local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.main(v_input)
  return M.__print((M.v_addGreeting)(v_input))
end

M.v_greeting = "Hello"

function M.v_addGreeting(v_name)
  return table.concat({M.v_greeting, ", ", v_name, "!"})
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
