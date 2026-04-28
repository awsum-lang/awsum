"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __parseUInt8(s){ if (!/^[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n > 255) return [0, [0]]; return [1, n & 0xFF]; }

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return "err";
        }
        case 1: {
          const v_v = __s[1];
          return ("ok:" + String(v_v));
        }
      }
    }
}

function main(v__input){
    return __print((((((((((((((((v_render)(__parseUInt8("0")) + ", ") + (v_render)(__parseUInt8("255"))) + ", ") + (v_render)(__parseUInt8("256"))) + ", ") + (v_render)(__parseUInt8("-1"))) + ", ") + (v_render)(__parseUInt8(""))) + ", ") + (v_render)(__parseUInt8("abc"))) + ", ") + (v_render)(__parseUInt8(" 5"))) + ", ") + (v_render)(__parseUInt8("12a"))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();