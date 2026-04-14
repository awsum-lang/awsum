local function __print(s) io.write(tostring(s)); return nil end

function v_handleA(v_step)
  return (function(s) if s[1] == 0 then return ("A" .. (v_handleB)({1})) elseif s[1] == 1 then return (v_handleB)(v_step) elseif s[1] == 2 then return (v_handleB)(v_step) elseif s[1] == 3 then return "" end end)(v_step)
end

function v_handleB(v_step)
  return (function(s) if s[1] == 0 then return (v_handleA)(v_step) elseif s[1] == 1 then return ("B" .. (v_handleA)({2})) elseif s[1] == 2 then return ("C" .. (v_handleA)({3})) elseif s[1] == 3 then return "" end end)(v_step)
end

function main(v_input)
  return __print((v_handleA)({0}))
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
