local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_not(v_b)
  return (function(s) if s[1] == 0 then return {1} elseif s[1] == 1 then return {0} end end)(v_b)
end

function M.v_and(v_a, v_b)
  return (function(s) if s[1] == 0 then return v_b elseif s[1] == 1 then return {1} end end)(v_a)
end

function M.v_or(v_a, v_b)
  return (function(s) if s[1] == 0 then return {0} elseif s[1] == 1 then return v_b end end)(v_a)
end

function M.v_showBool(v_b)
  return (function(s) if s[1] == 0 then return "T" elseif s[1] == 1 then return "F" end end)(v_b)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_showBool)((M.v_not)({0})), (M.v_showBool)((M.v_not)({1})), (M.v_showBool)((M.v_and)({0}, {1})), (M.v_showBool)((M.v_and)({0}, {0})), (M.v_showBool)((M.v_or)({1}, {1})), (M.v_showBool)((M.v_or)({0}, {1}))}))
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
