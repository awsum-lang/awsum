local function __print(s) io.write(tostring(s)); return nil end

function v_map(v_f, v_list)
  return (function(s) if s[1] == 0 then local v_head = s[2]; local v_tail = s[3]; return {0, (v_f)(v_head), (v_map)(v_f, v_tail)} elseif s[1] == 1 then return {1} end end)(v_list)
end

function v_show(v_xs)
  return (function(s) if s[1] == 0 then local v_h = s[2]; local v_t = s[3]; return table.concat({v_h, ",", (v_show)(v_t)}) elseif s[1] == 1 then return "" end end)(v_xs)
end

function v_shout(v_s)
  return (v_s .. "!")
end

function main(v__input)
  return __print((v_show)((v_map)(v_shout, {0, "a", {0, "b", {0, "c", {1}}}})))
end

function v__con_Cons(v__x0, v__x1)
  return {0, v__x0, v__x1}
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
