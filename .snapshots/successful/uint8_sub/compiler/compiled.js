"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __subUInt8(a, b){ const d = a - b; return d < 0 ? [0, [0]] : [1, d & 0xFF]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

const v_minUInt8 = (0 & 0xFF);

const v_maxUInt8 = (255 & 0xFF);

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return ("underflow: " + (v_showUnderflowError)(v_e));
        }
        case 1: {
          const v_v = __s[1];
          return ("ok: " + String(v_v));
        }
      }
    }
}

function main(v__input){
    return __print((((((((v_render)(__subUInt8((5 & 0xFF), (5 & 0xFF))) + ", ") + (v_render)(__subUInt8(v_maxUInt8, v_minUInt8))) + ", ") + (v_render)(__subUInt8(v_minUInt8, (1 & 0xFF)))) + ", ") + (v_render)(__subUInt8(v_minUInt8, v_maxUInt8))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();