local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__predUInt8(x) if x == 0 then return {0, {0}} else return {1, x - 1} end end
function M.__eqUInt8(a, b) if a == b then return {0} else return {1} end end

function M.v_showUnderflowError(v__wild0)
  return "UnderflowError"
end

M.v_zero = 0

function M.v_countDown(v_n)
  return (M.v__cps_countDown)(v_n, {0})
end

function M.v__cps_countDown(v_n, v__k)
  while true do
    local __s = M.__eqUInt8(v_n, M.v_zero)
    if __s[1] == 0 then
      return (M.v__apply_countDown)(v__k, {1, tostring(v_n)})
    elseif __s[1] == 1 then
      local __s = M.__predUInt8(v_n)
      if __s[1] == 0 then
        local v_e = __s[2]
        return (M.v__apply_countDown)(v__k, {0, v_e})
      elseif __s[1] == 1 then
        local v_m = __s[2]
        local __t0 = v_m
        local __t1 = {1, v__k, v_n}
        v_n = __t0
        v__k = __t1
      end
    end
  end
end

function M.v__apply_countDown(v__k, v__x)
  while true do
    local __s = v__k
    if __s[1] == 0 then
      return v__x
    elseif __s[1] == 1 then
      local v__pk_1 = __s[2]
      local v_n = __s[3]
      local __s = v__x
      if __s[1] == 0 then
        local v_e = __s[2]
        local __t0 = v__pk_1
        local __t1 = {0, v_e}
        v__k = __t0
        v__x = __t1
      elseif __s[1] == 1 then
        local v_s = __s[2]
        local __t0 = v__pk_1
        local __t1 = {1, table.concat({tostring(v_n), ",", v_s})}
        v__k = __t0
        v__x = __t1
      end
    end
  end
end

function M.v_showResult(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("left: " .. (M.v_showUnderflowError)(v_e)) elseif s[1] == 1 then local v_s = s[2]; return ("right: " .. v_s) end end)(v_r)
end

M.v_start = 255

function M.main(v__input)
  return M.__print((M.v_showResult)((M.v_countDown)(M.v_start)))
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
