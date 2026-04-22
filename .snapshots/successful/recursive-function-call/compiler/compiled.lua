local function __print(s) io.write(tostring(s)); return nil end

function v_advanceStep(v_x)
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

function main(v__input)
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
