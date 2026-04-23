local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

M.v_zero = 0

function M.main(v__input)
  return M.__print(tostring((M.v_parseExpr)({1})))
end

function M.v__scc_parseBinary_parseExpr(v__args)
  while true do
    local __s = v__args
    if __s[1] == 0 then
      local v_tok = __s[2]
      local v__acc = __s[3]
      local __s = v_tok
      if __s[1] == 0 then
        return M.v_zero
      elseif __s[1] == 1 then
        local __t0 = {1, {0}}
        v__args = __t0
      end
    elseif __s[1] == 1 then
      local v_tok = __s[2]
      local __s = v_tok
      if __s[1] == 0 then
        return M.v_zero
      elseif __s[1] == 1 then
        local __t0 = {0, v_tok, M.v_zero}
        v__args = __t0
      end
    end
  end
end

function M.v_parseBinary(v_tok, v__acc)
  return (M.v__scc_parseBinary_parseExpr)({0, v_tok, v__acc})
end

function M.v_parseExpr(v_tok)
  return (M.v__scc_parseBinary_parseExpr)({1, v_tok})
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
