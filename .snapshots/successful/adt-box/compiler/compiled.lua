local function __print(s) io.write(tostring(s)); return nil end

function v_unwrap(v_b)
  return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value end end)(v_b)
end

function main(v_input)
  return __print((v_unwrap)({0, "hello"}))
end

function v__con_Box(v__x0)
  return {0, v__x0}
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
