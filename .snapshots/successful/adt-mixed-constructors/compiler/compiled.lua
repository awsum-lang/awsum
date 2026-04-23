local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_showToken(v_token)
  return (function(s) if s[1] == 0 then local v_w = s[2]; return ("word:" .. v_w) elseif s[1] == 1 then local v_n = s[2]; return ("num:" .. v_n) elseif s[1] == 2 then return "," elseif s[1] == 3 then return "<eof>" end end)(v_token)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_showToken)({0, "hello"}), " ", (M.v_showToken)({2}), " ", (M.v_showToken)({1, "42"}), " ", (M.v_showToken)({3})}))
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
