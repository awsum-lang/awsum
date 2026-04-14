local function __print(s) io.write(tostring(s)); return nil end

function v_advanceStep(v_x)
  return (function(s) if s[1] == 0 then return (v_advanceStep)({1}) elseif s[1] == 1 then return (v_advanceStep)({2}) elseif s[1] == 2 then return "Done!" end end)(v_x)
end

function main(v_input)
  return __print((v_advanceStep)({0}))
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
