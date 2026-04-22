"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predInt32(x){ return x === -2147483648 ? [0, [0]] : [1, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [0] : [1]; }

function v_countDown(v_n, v_acc){
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 0: {
          return v_acc;
        }
        case 1: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 0: {
                const v___w0 = __s[1];
                return v_acc;
              }
              case 1: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = v_acc;
                v_n = __t0;
                v_acc = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

const v_start = (100000|0);

function main(v__input){
  return __print((v_countDown)(v_start, "done"));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
