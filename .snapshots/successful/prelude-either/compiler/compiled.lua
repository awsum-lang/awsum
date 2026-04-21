local function __print(s) io.write(tostring(s)); return nil end

function v_unwrap(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("left: " .. v_e) elseif s[1] == 1 then local v_v = s[2]; return ("right: " .. v_v) end end)(v_r)
end

function main(v__input)
  return __print(table.concat({(v_unwrap)({0, "bad"}), ", ", (v_unwrap)({1, "good"})}))
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
