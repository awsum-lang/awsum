local function __print(s) io.write(tostring(s)); return nil end
local function __eqInt32(a, b) if a == b then return {0} else return {1} end end

function v_render(v_b)
  return (function(s) if s[1] == 0 then return "T" elseif s[1] == 1 then return "F" end end)(v_b)
end

v_minInt32 = -2147483648

function main(v__input)
  return __print(table.concat({(v_render)(__eqInt32(42, 42)), (v_render)(__eqInt32(42, 7)), (v_render)(__eqInt32(v_minInt32, v_minInt32)), (v_render)(__eqInt32(0, 1))}))
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
