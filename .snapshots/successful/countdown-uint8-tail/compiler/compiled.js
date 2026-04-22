"use strict";
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }

function v_countDown(v_n, v_acc){
  while (true) {
    {
      const __s = __predUInt8(v_n);
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return (v_acc + String(v_n));
        }
        case 1: {
          const v_m = __s[1];
          const __t0 = v_m;
          const __t1 = ((v_acc + String(v_n)) + ",");
          v_n = __t0;
          v_acc = __t1;
          continue;
        }
      }
    }
  }
}

function main(v__input){
  return __print((v_countDown)((255 & 0xFF), ""));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}
