"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __parseInt32(s){ if (!/^-?[0-9]+$/.test(s)) return [0, [0]]; const n = Number(s); if (n < -2147483648 || n > 2147483647) return [0, [0]]; return [1, n | 0]; }

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
    return __print((((((((((((((((((((((((v_render)(__parseInt32("42")) + ", ") + (v_render)(__parseInt32("-42"))) + ", ") + (v_render)(__parseInt32("0"))) + ", ") + (v_render)(__parseInt32("2147483647"))) + ", ") + (v_render)(__parseInt32("-2147483648"))) + ", ") + (v_render)(__parseInt32("2147483648"))) + ", ") + (v_render)(__parseInt32("-2147483649"))) + ", ") + (v_render)(__parseInt32(""))) + ", ") + (v_render)(__parseInt32("-"))) + ", ") + (v_render)(__parseInt32("+42"))) + ", ") + (v_render)(__parseInt32(" 42"))) + ", ") + (v_render)(__parseInt32("12abc"))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();