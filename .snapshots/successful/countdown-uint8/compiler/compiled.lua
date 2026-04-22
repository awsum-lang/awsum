local function __print(s) io.write(tostring(s)); return nil end
local function __predUInt8(x) if x == 0 then return {0, {0}} else return {1, x - 1} end end

function v_countDown(v_n)
  return (function(s) if s[1] == 0 then local v___w0 = s[2]; return tostring(v_n) elseif s[1] == 1 then local v_m = s[2]; return table.concat({tostring(v_n), ",", (v_countDown)(v_m)}) end end)(__predUInt8(v_n))
end

function main(v__input)
  return __print((v_countDown)(255))
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
