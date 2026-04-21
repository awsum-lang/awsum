local function __print(s) io.write(tostring(s)); return nil end

function v_show(v_xs)
  return (function(s) if s[1] == 0 then local v_h = s[2]; local v_t = s[3]; return table.concat({v_h, ",", (v_show)(v_t)}) elseif s[1] == 1 then return "" end end)(v_xs)
end

v_exampleList = {0, "a", {0, "b", {0, "c", {1}}}}

function main(v__input)
  return __print((v_show)(v_exampleList))
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
