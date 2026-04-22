local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_greeting(v__wild0)
  return "hi"
end

function M.v_unwrapBox(v_b)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; return "unwrapped" end end)(v_b)
end

function M.v_unwrapBoxNamed(v_b)
  return (function(s) if s[1] == 0 then local v__v = s[2]; return "unwrapped-named" end end)(v_b)
end

function M.v_showPair(v_p)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; local v___w1 = s[3]; return "paired" end end)(v_p)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_greeting)("x"), " ", (M.v_unwrapBox)({0, "a"}), " ", (M.v_unwrapBoxNamed)({0, "b"}), " ", (M.v_showPair)({0, "l", "r"})}))
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
