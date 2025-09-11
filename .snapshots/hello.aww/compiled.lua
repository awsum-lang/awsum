local function __print(s) io.write(tostring(s)); return nil end

function main(v_input)
  return __print((v_addGreeting)(v_input))
end

function v_addGreeting(v_name)
  return (((v_greeting .. ", ") .. v_name) .. "!")
end

v_greeting = "Hello"

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
