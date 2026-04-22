local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_map(v_f, v_list)
  return (function(s) if s[1] == 0 then local v_head = s[2]; local v_tail = s[3]; return {0, (v_f)(v_head), (M.v_map)(v_f, v_tail)} elseif s[1] == 1 then return {1} end end)(v_list)
end

function M.v_show(v_xs)
  return (function(s) if s[1] == 0 then local v_h = s[2]; local v_t = s[3]; return table.concat({v_h, ",", (M.v_show)(v_t)}) elseif s[1] == 1 then return "" end end)(v_xs)
end

function M.v_shout(v_s)
  return (v_s .. "!")
end

function M.main(v__input)
  return M.__print((M.v_show)((M.v_map)(M.v_shout, {0, "a", {0, "b", {0, "c", {1}}}})))
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
