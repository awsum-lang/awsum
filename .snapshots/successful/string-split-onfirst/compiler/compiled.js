"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __splitOnFirst(sep, str){ const i = str.indexOf(sep); if (i < 0) return [0]; return [1, [0, str.substring(0, i), str.substring(i + sep.length)]]; }

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          return "Nothing";
        }
        case 1: {
          const v_t = __s[1];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 0: {
                const v_a = __s[1];
                const v_b = __s[2];
                return (((("Just(" + v_a) + "|") + v_b) + ")");
              }
            }
          }
        }
      }
    }
}

function main(v__input){
    return __print((((((((((((((((v_render)(__splitOnFirst(",", "a,b,c")) + ", ") + (v_render)(__splitOnFirst("::", "user::42::admin"))) + ", ") + (v_render)(__splitOnFirst("x", "abc"))) + ", ") + (v_render)(__splitOnFirst("", "abc"))) + ", ") + (v_render)(__splitOnFirst(":", ":foo"))) + ", ") + (v_render)(__splitOnFirst(":", "foo:"))) + ", ") + (v_render)(__splitOnFirst("abc", "abc"))) + ", ") + (v_render)(__splitOnFirst("abcde", "ab"))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();