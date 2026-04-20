local function __print(s) io.write(tostring(s)); return nil end

function v_colorName(v_c)
  return (function(s) if s[1] == 0 then return "red" elseif s[1] == 1 then return "green" elseif s[1] == 2 then return "blue" end end)(v_c)
end

function v_showBoxedColor(v_bc)
  return (function(s) if s[1] == 0 then local v_c = s[2]; return (v_colorName)(v_c) end end)(v_bc)
end

function v_showResult(v_r)
  return (function(s) if s[1] == 0 then local v_box = s[2]; return (v_showBoxedColor)(v_box) elseif s[1] == 1 then local v_e = s[2]; return v_e end end)(v_r)
end

function main(v_input)
  return __print(table.concat({(v_showBoxedColor)({0, {0}}), " ", (v_showResult)({0, {0, {1}}})}))
end

function v__con_Box(v__x0)
  return {0, v__x0}
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
