local function __print(s) io.write(tostring(s)); return nil end

function v_showPair(v_pair)
  return (function(s) if s[1] == 0 then local v_first = s[2]; local v_second = s[3]; return table.concat({"(", v_first, ", ", v_second, ")"}) end end)(v_pair)
end

function main(v_input)
  return __print((v_showPair)({0, "hello", "world"}))
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
