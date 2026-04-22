local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.main(v__input)
  return M.__print(table.concat({tostring(M.v_minUInt8), ", ", tostring(M.v_small), ", ", tostring(M.v_aboveSignedByte), ", ", tostring(M.v_maxUInt8)}))
end

M.v_minUInt8 = 0

M.v_small = 42

M.v_aboveSignedByte = 200

M.v_maxUInt8 = 255

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
  if type(M.main) == 'function' then M.main(input) end
end
