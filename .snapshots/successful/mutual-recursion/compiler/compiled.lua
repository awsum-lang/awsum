local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.main(v__input)
  return M.__print((M.v_handleA)({0}))
end

function M.v__scc_handleA_handleB(v__args)
  return (M.v__cps__scc_handleA_handleB)(v__args, {0})
end

function M.v__cps__scc_handleA_handleB(v__args, v__k)
  while true do
    local __s = v__args
    if __s[1] == 0 then
      local v_step = __s[2]
      local __s = v_step
      if __s[1] == 0 then
        local __t0 = {1, {1}}
        local __t1 = {1, v__k}
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 1 then
        local __t0 = {1, v_step}
        local __t1 = v__k
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 2 then
        local __t0 = {1, v_step}
        local __t1 = v__k
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 3 then
        return (M.v__apply__scc_handleA_handleB)(v__k, "")
      end
    elseif __s[1] == 1 then
      local v_step = __s[2]
      local __s = v_step
      if __s[1] == 0 then
        local __t0 = {0, v_step}
        local __t1 = v__k
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 1 then
        local __t0 = {0, {2}}
        local __t1 = {2, v__k}
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 2 then
        local __t0 = {0, {3}}
        local __t1 = {3, v__k}
        v__args = __t0
        v__k = __t1
      elseif __s[1] == 3 then
        return (M.v__apply__scc_handleA_handleB)(v__k, "")
      end
    end
  end
end

function M.v__apply__scc_handleA_handleB(v__k, v__x)
  while true do
    local __s = v__k
    if __s[1] == 0 then
      return v__x
    elseif __s[1] == 1 then
      local v__pk_1 = __s[2]
      local __t0 = v__pk_1
      local __t1 = ("A" .. v__x)
      v__k = __t0
      v__x = __t1
    elseif __s[1] == 2 then
      local v__pk_2 = __s[2]
      local __t0 = v__pk_2
      local __t1 = ("B" .. v__x)
      v__k = __t0
      v__x = __t1
    elseif __s[1] == 3 then
      local v__pk_3 = __s[2]
      local __t0 = v__pk_3
      local __t1 = ("C" .. v__x)
      v__k = __t0
      v__x = __t1
    end
  end
end

function M.v_handleA(v_step)
  return (M.v__scc_handleA_handleB)({0, v_step})
end

function M.v_handleB(v_step)
  return (M.v__scc_handleA_handleB)({1, v_step})
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
