local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_wrap(v_s)
  return {0, v_s}
end

function M.v_unwrap(v_b)
  return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value end end)(v_b)
end

function M.v_apply(v_f, v_x)
  return (v_f)(v_x)
end

function M.v_compose(v_f, v_g, v_x)
  return (v_f)((v_g)(v_x))
end

function M.main(v__input)
  return M.__print((M.v_apply)(M.v__pap_0, "chain"))
end

function M.v__pap_0(v__eta0)
  return (M.v_compose)(M.v_unwrap, M.v_wrap, v__eta0)
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
