local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_advanceStep(v_x)
  while true do
    local __s = v_x
    if __s[1] == 0 then
      local __t0 = {1}
      v_x = __t0
    elseif __s[1] == 1 then
      local __t0 = {2}
      v_x = __t0
    elseif __s[1] == 2 then
      return "Done!"
    end
  end
end

function M.main(v__input)
  return M.__print((M.v_advanceStep)({0}))
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
  if type(M.main) == 'function' then M.main(input) end
end
