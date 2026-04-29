"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

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

const v_minInt32 = (-2147483648|0);

const v_ordinary = (42|0);

function main(v__input){
    return __print((((v_render)(__predInt32(v_ordinary)) + ", ") + (v_render)(__predInt32(v_minInt32))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();