local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_unwrap(v_r)
  return (function(s) if s[1] == 0 then local v_inner1 = s[2]; return (function(s) if s[1] == 0 then local v_inner2 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v_inner2) elseif s[1] == 1 then local v_inner2 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v_inner2) end end)(v_inner1) elseif s[1] == 1 then local v_inner1 = s[2]; return (function(s) if s[1] == 0 then local v_inner2 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v_inner2) elseif s[1] == 1 then local v_inner2 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v_inner2) end end)(v_inner1) end end)(v_r)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_unwrap)({0, {0, {0, "1"}}}), ",", (M.v_unwrap)({0, {0, {1, "2"}}}), ",", (M.v_unwrap)({0, {1, {0, "3"}}}), ",", (M.v_unwrap)({0, {1, {1, "4"}}}), ",", (M.v_unwrap)({1, {0, {0, "5"}}}), ",", (M.v_unwrap)({1, {0, {1, "6"}}}), ",", (M.v_unwrap)({1, {1, {0, "7"}}}), ",", (M.v_unwrap)({1, {1, {1, "8"}}})}))
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
