local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__predInt32(x) if x == -2147483648 then return {0, {0}} else return {1, x - 1} end end
function M.__eqInt32(a, b) if a == b then return {0} else return {1} end end

function M.v_countDown(v_n, v_acc)
  while true do
    local __s = M.__eqInt32(v_n, 0)
    if __s[1] == 0 then
      return v_acc
    elseif __s[1] == 1 then
      local __s = M.__predInt32(v_n)
      if __s[1] == 0 then
        local v___w0 = __s[2]
        return v_acc
      elseif __s[1] == 1 then
        local v_m = __s[2]
        local __t0 = v_m
        local __t1 = v_acc
        v_n = __t0
        v_acc = __t1
      end
    end
  end
end

M.v_start = 100000

function M.main(v__input)
  return M.__print((M.v_countDown)(M.v_start, "done"))
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
