"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __mulInt32(a, b){ const p = a * b; if (p > 2147483647) return [0, [882564211, [0]]]; if (p < -2147483648) return [0, [3768445577, [0]]]; return [1, p|0]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_showOverflowError(v__wild0){
    return "OverflowError";
}

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 882564211: {
                const v_o = __s[1];
                return ("err: " + (v_showOverflowError)(v_o));
              }
              case 3768445577: {
                const v_u = __s[1];
                return ("err: " + (v_showUnderflowError)(v_u));
              }
            }
          }
        }
        case 1: {
          const v_v = __s[1];
          return ("ok: " + String(v_v));
        }
      }
    }
}

const v_minInt32 = (-2147483648|0);

function main(v__input){
    return __print((((((((((((v_render)(__mulInt32((6|0), (7|0))) + ", ") + (v_render)(__mulInt32((-6|0), (7|0)))) + ", ") + (v_render)(__mulInt32((100000|0), (100000|0)))) + ", ") + (v_render)(__mulInt32((-100000|0), (100000|0)))) + ", ") + (v_render)(__mulInt32(v_minInt32, (-1|0)))) + ", ") + (v_render)(__mulInt32(v_minInt32, (1|0)))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();