local function __print(s) io.write(tostring(s)); return nil end

function v_greeting(v__wild0)
  return "hi"
end

function v_unwrapBox(v_b)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; return "unwrapped" end end)(v_b)
end

function v_unwrapBoxNamed(v_b)
  return (function(s) if s[1] == 0 then local v__v = s[2]; return "unwrapped-named" end end)(v_b)
end

function v_showPair(v_p)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; local v___w1 = s[3]; return "paired" end end)(v_p)
end

function main(v__input)
  return __print(table.concat({(v_greeting)("x"), " ", (v_unwrapBox)({0, "a"}), " ", (v_unwrapBoxNamed)({0, "b"}), " ", (v_showPair)({0, "l", "r"})}))
end

function v__con_Box(v__x0)
  return {0, v__x0}
end

function v__con_Pair(v__x0, v__x1)
  return {0, v__x0, v__x1}
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
