local function __print(s) io.write(tostring(s)); return nil end

function v_identity(v_x)
  return v_x
end

function main(v_input)
  return __print((function(s) if s[1] == 0 then local v_v = s[2]; return v_v end end)((v_identity)({0, "one"})))
end

function v__con_Box(v__x0)
  return {0, v__x0}
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
