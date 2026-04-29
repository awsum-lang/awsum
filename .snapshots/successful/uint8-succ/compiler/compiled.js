"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __succUInt8(x){ return x === 255 ? [0, [0]] : [1, ((x + 1) & 0xFF)]; }

function v_showOverflowError(v__wild0){
    return "OverflowError";
}

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          return ("overflow: " + (v_showOverflowError)(v_e));
        }
        case 1: {
          const v_v = __s[1];
          return ("ok: " + String(v_v));
        }
      }
    }
}

function main(v__input){
    return __print((((((v_render)(__succUInt8((255 & 0xFF))) + ", ") + (v_render)(__succUInt8((254 & 0xFF)))) + ", ") + (v_render)(__succUInt8((0 & 0xFF)))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();