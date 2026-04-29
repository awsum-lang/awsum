"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __eqUInt8(a, b){ return a === b ? [0] : [1]; }

function v_render(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return "T";
        }
        case 1: {
          return "F";
        }
      }
    }
}

function main(v__input){
    return __print(((((v_render)(__eqUInt8((0 & 0xFF), (0 & 0xFF))) + (v_render)(__eqUInt8((255 & 0xFF), (255 & 0xFF)))) + (v_render)(__eqUInt8((255 & 0xFF), (0 & 0xFF)))) + (v_render)(__eqUInt8((128 & 0xFF), (127 & 0xFF)))));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();