local function __print(s) io.write(tostring(s)); return nil end

function v_unwrap(v_r)
  return (function(s) if s[1] == 0 then local v___p0 = s[2]; return (function(s) if s[1] == 0 then local v___p0_p0 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v___p0_p0) elseif s[1] == 1 then local v___p0_p0 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v___p0_p0) end end)(v___p0) elseif s[1] == 1 then local v___p0 = s[2]; return (function(s) if s[1] == 0 then local v___p0_p0 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v___p0_p0) elseif s[1] == 1 then local v___p0_p0 = s[2]; return (function(s) if s[1] == 0 then local v_value = s[2]; return v_value elseif s[1] == 1 then local v_value = s[2]; return v_value end end)(v___p0_p0) end end)(v___p0) end end)(v_r)
end

function main(v__input)
  return __print(table.concat({(v_unwrap)({0, {0, {0, "1"}}}), ",", (v_unwrap)({0, {0, {1, "2"}}}), ",", (v_unwrap)({0, {1, {0, "3"}}}), ",", (v_unwrap)({0, {1, {1, "4"}}}), ",", (v_unwrap)({1, {0, {0, "5"}}}), ",", (v_unwrap)({1, {0, {1, "6"}}}), ",", (v_unwrap)({1, {1, {0, "7"}}}), ",", (v_unwrap)({1, {1, {1, "8"}}})}))
end

function v__con_Err(v__x0)
  return {1, v__x0}
end

function v__con_Ok(v__x0)
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
