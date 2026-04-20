local function __print(s) io.write(tostring(s)); return nil end

function main(v__input)
  return __print(table.concat({tostring(v_minUInt8), ", ", tostring(v_small), ", ", tostring(v_aboveSignedByte), ", ", tostring(v_maxUInt8)}))
end

v_minUInt8 = 0

v_small = 42

v_aboveSignedByte = 200

v_maxUInt8 = 255

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
