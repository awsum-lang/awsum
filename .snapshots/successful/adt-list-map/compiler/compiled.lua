local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.v_map(v_f, v_list)
  return (M.v__cps_map)(v_f, v_list, {0})
end

function M.v__cps_map(v_f, v_list, v__k)
  while true do
    local __s = v_list
    if __s[1] == 0 then
      local v_head = __s[2]
      local v_tail = __s[3]
      local __t0 = v_f
      local __t1 = v_tail
      local __t2 = {1, v__k, v_f, v_head}
      v_f = __t0
      v_list = __t1
      v__k = __t2
    elseif __s[1] == 1 then
      return (M.v__apply_map)(v__k, {1})
    end
  end
end

function M.v__apply_map(v__k, v__x)
  while true do
    local __s = v__k
    if __s[1] == 0 then
      return v__x
    elseif __s[1] == 1 then
      local v__pk_1 = __s[2]
      local v_f = __s[3]
      local v_head = __s[4]
      local __t0 = v__pk_1
      local __t1 = {0, (v_f)(v_head), v__x}
      v__k = __t0
      v__x = __t1
    end
  end
end

function M.v_show(v_xs)
  return (M.v__cps_show)(v_xs, {0})
end

function M.v__cps_show(v_xs, v__k)
  while true do
    local __s = v_xs
    if __s[1] == 0 then
      local v_h = __s[2]
      local v_t = __s[3]
      local __t0 = v_t
      local __t1 = {1, v__k, v_h}
      v_xs = __t0
      v__k = __t1
    elseif __s[1] == 1 then
      return (M.v__apply_show)(v__k, "")
    end
  end
end

function M.v__apply_show(v__k, v__x)
  while true do
    local __s = v__k
    if __s[1] == 0 then
      return v__x
    elseif __s[1] == 1 then
      local v__pk_1 = __s[2]
      local v_h = __s[3]
      local __t0 = v__pk_1
      local __t1 = table.concat({v_h, ",", v__x})
      v__k = __t0
      v__x = __t1
    end
  end
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
