local function __print(s) io.write(tostring(s)); return nil end

function v_show(v_u)
  return (function(s) if s[1] == 0 then return "Unit" end end)(v_u)
end

function main(v__input)
  return __print((v_show)({0}))
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
