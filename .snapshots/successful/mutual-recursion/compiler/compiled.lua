local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_handleA(v_step)
  return (function(s) if s[1] == 0 then return ("A" .. (M.v_handleB)({1})) elseif s[1] == 1 then return (M.v_handleB)(v_step) elseif s[1] == 2 then return (M.v_handleB)(v_step) elseif s[1] == 3 then return "" end end)(v_step)
end

function M.v_handleB(v_step)
  return (function(s) if s[1] == 0 then return (M.v_handleA)(v_step) elseif s[1] == 1 then return ("B" .. (M.v_handleA)({2})) elseif s[1] == 2 then return ("C" .. (M.v_handleA)({3})) elseif s[1] == 3 then return "" end end)(v_step)
end

function M.main(v__input)
  return M.__print((M.v_handleA)({0}))
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
