local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_colorName(v_c)
  return (function(s) if s[1] == 0 then return "red" elseif s[1] == 1 then return "green" elseif s[1] == 2 then return "blue" end end)(v_c)
end

function M.v_showBoxedColor(v_bc)
  return (function(s) if s[1] == 0 then local v_c = s[2]; return (M.v_colorName)(v_c) end end)(v_bc)
end

function M.v_showResult(v_r)
  return (function(s) if s[1] == 0 then local v_box = s[2]; return (M.v_showBoxedColor)(v_box) elseif s[1] == 1 then local v_e = s[2]; return v_e end end)(v_r)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_showBoxedColor)({0, {0}}), " ", (M.v_showResult)({0, {0, {1}}})}))
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
