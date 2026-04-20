local function __print(s) io.write(tostring(s)); return nil end

function v_showTriple(v_t)
  return (function(s) if s[1] == 0 then local v_a = s[2]; local v_b = s[3]; local v_c = s[4]; return table.concat({v_a, " ", v_b, " ", v_c}) end end)(v_t)
end

function main(v__input)
  return __print((v_showTriple)({0, "one", "two", "three"}))
end

function v__con_Triple(v__x0, v__x1, v__x2)
  return {0, v__x0, v__x1, v__x2}
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
