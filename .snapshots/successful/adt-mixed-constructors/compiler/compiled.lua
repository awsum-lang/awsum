local function __print(s) io.write(tostring(s)); return nil end

function v_showToken(v_token)
  return (function(s) if s[1] == 0 then local v_w = s[2]; return ("word:" .. v_w) elseif s[1] == 1 then local v_n = s[2]; return ("num:" .. v_n) elseif s[1] == 2 then return "," elseif s[1] == 3 then return "<eof>" end end)(v_token)
end

function main(v_input)
  return __print((((((((v_showToken)({0, "hello"}) .. " ") .. (v_showToken)({2})) .. " ") .. (v_showToken)({1, "42"})) .. " ") .. (v_showToken)({3})))
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
  if type(main) == 'function' then main(input) end
end
