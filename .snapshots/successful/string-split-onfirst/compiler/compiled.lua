local M = {}

function M.__print(s) io.write(tostring(s)); return nil end
function M.__splitOnFirst(sep, str) if sep == "" then return {1, {0, "", str}} end local i, j = string.find(str, sep, 1, true) if i == nil then return {0} end return {1, {0, string.sub(str, 1, i - 1), string.sub(str, j + 1)}} end

function M.v_render(v_r)
  return (function(s) if s[1] == 0 then return "Nothing" elseif s[1] == 1 then local v_t = s[2]; return (function(s) if s[1] == 0 then local v_a = s[2]; local v_b = s[3]; return table.concat({"Just(", v_a, "|", v_b, ")"}) end end)(v_t) end end)(v_r)
end

function M.main(v__input)
  return M.__print(table.concat({(M.v_render)(M.__splitOnFirst(",", "a,b,c")), ", ", (M.v_render)(M.__splitOnFirst("::", "user::42::admin")), ", ", (M.v_render)(M.__splitOnFirst("x", "abc")), ", ", (M.v_render)(M.__splitOnFirst("", "abc")), ", ", (M.v_render)(M.__splitOnFirst(":", ":foo")), ", ", (M.v_render)(M.__splitOnFirst(":", "foo:")), ", ", (M.v_render)(M.__splitOnFirst("abc", "abc")), ", ", (M.v_render)(M.__splitOnFirst("abcde", "ab"))}))
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
