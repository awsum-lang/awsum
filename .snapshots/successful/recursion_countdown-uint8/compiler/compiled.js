"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predUInt8(x){ return x === 0 ? [0, [0]] : [1, ((x - 1) & 0xFF)]; }
function __eqUInt8(a, b){ return a === b ? [0] : [1]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_showUnderflowError(v__wild0){
    return "UnderflowError";
}

function v_countDown(v_n){
    return (v__cps_countDown)(v_n, [0]);
}

function v__cps_countDown(v_n, v__k){
  while (true) {
    {
      const __s = __eqUInt8(v_n, (0 & 0xFF));
      switch (__s[0]) {
        case 0: {
          return (v__apply_countDown)(v__k, [1, String(v_n)]);
        }
        case 1: {
          {
            const __s = __predUInt8(v_n);
            switch (__s[0]) {
              case 0: {
                const v_e = __s[1];
                return (v__apply_countDown)(v__k, [0, [3768445577, v_e]]);
              }
              case 1: {
                const v_m = __s[1];
                const __t0 = v_m;
                const __t1 = [1, v__k, v_n];
                v_n = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v__apply_countDown(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_n = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v_e = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [0, v_e];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_s = __s[1];
                {
                  const __s = __concat(String(v_n), ",");
                  switch (__s[0]) {
                    case 0: {
                      const v_e = __s[1];
                      const __t0 = v__pk_1;
                      const __t1 = [0, [3768445577, v_e]];
                      v__k = __t0;
                      v__x = __t1;
                      continue;
                    }
                    case 1: {
                      const v_s0 = __s[1];
                      const __t0 = v__pk_1;
                      const __t1 = __concat(v_s0, v_s);
                      v__k = __t0;
                      v__x = __t1;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 589989748: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 0: {
                      return [1, "STRING_TOO_LONG"];
                    }
                  }
                }
              }
              case 3768445577: {
                const v_u = __s[1];
                return __concat("left: ", (v_showUnderflowError)(v_u));
              }
            }
          }
        }
        case 1: {
          const v_s = __s[1];
          return __concat("right: ", v_s);
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_showResult)((v_countDown)((255 & 0xFF))));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();