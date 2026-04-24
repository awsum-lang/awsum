local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__predInt32(x) if x == -2147483648 then return {0, {0}} else return {1, x - 1} end end
function M.__eqInt32(a, b) if a == b then return {0} else return {1} end end

function M.v_showUnderflowError(v__wild0)
  return "UnderflowError"
end

M.v_zero = 0

function M.v_showBool(v_b)
  return (function(s) if s[1] == 0 then return "true" elseif s[1] == 1 then return "false" end end)(v_b)
end

function M.v_showResult(v_r)
  return (function(s) if s[1] == 0 then local v_e = s[2]; return ("left: " .. (M.v_showUnderflowError)(v_e)) elseif s[1] == 1 then local v_b = s[2]; return ("right: " .. (M.v_showBool)(v_b)) end end)(v_r)
end

M.v_start = 1000000

function M.main(v__input)
  return M.__print((M.v_showResult)((M.v_evenInt)(M.v_start)))
end

function M.v__scc_evenInt_oddInt(v__args)
  while true do
    local __s = v__args
    if __s[1] == 0 then
      local v_n = __s[2]
      local __s = M.__eqInt32(v_n, M.v_zero)
      if __s[1] == 0 then
        return {1, {0}}
      elseif __s[1] == 1 then
        local __s = M.__predInt32(v_n)
        if __s[1] == 0 then
          local v_e = __s[2]
          return {0, v_e}
        elseif __s[1] == 1 then
          local v_m = __s[2]
          local __t0 = {1, v_m}
          v__args = __t0
        end
      end
    elseif __s[1] == 1 then
      local v_n = __s[2]
      local __s = M.__eqInt32(v_n, M.v_zero)
      if __s[1] == 0 then
        return {1, {1}}
      elseif __s[1] == 1 then
        local __s = M.__predInt32(v_n)
        if __s[1] == 0 then
          local v_e = __s[2]
          return {0, v_e}
        elseif __s[1] == 1 then
          local v_m = __s[2]
          local __t0 = {0, v_m}
          v__args = __t0
        end
      end
    end
  end
end

function M.v_evenInt(v_n)
  return (M.v__scc_evenInt_oddInt)({0, v_n})
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
