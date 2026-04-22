local function __print(s) io.write(tostring(s)); return nil end
local function __predInt32(x) if x == -2147483648 then return {0, {0}} else return {1, x - 1} end end

function v_showUnderflowError(v__wild0)
  return "UnderflowError"
end

function v_render(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("underflow: " .. (v_showUnderflowError)(v_e)) elseif s[1] == 1 then local v_v = s[2]; return ("ok: " .. tostring(v_v)) end end)(v_r)
end

v_minInt32 = -2147483648

v_ordinary = 42

function main(v__input)
  return __print(table.concat({(v_render)(__predInt32(v_ordinary)), ", ", (v_render)(__predInt32(v_minInt32))}))
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
