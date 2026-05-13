"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [13]] : [4, ((x - 1)|0)]; }
function __eqInt32(a, b){ return a === b ? [1] : [2]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [15]] : [4, a + b]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_u = __s[1];
          return v_u;
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = null;
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

function v_double(v_n, v_s){
  while (true) {
    {
      const __s = __eqInt32(v_n, (0|0));
      switch (__s[0]) {
        case 1: {
          return [4, v_s];
        }
        case 2: {
          {
            const __s = __predInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v_ue = __s[1];
                return [3, [3768445577, v_ue]];
              }
              case 4: {
                const v_m = __s[1];
                {
                  const __s = __concat(v_s, v_s);
                  switch (__s[0]) {
                    case 3: {
                      const v_se = __s[1];
                      return [3, [589989748, v_se]];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      const __t0 = v_m;
                      const __t1 = v_s2;
                      v_s = null;
                      v_n = null;
                      v_n = __t0;
                      v_s = __t1;
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

const main = ((s) => { switch(s[0]) { case 3: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 589989748: { const v__t = s[1]; return [7, "string-too-long", [5, [0]]]; } case 3768445577: { const v__u = s[1]; return [7, "underflow", [5, [0]]]; } } })(v_e); } case 4: { const v__s = s[1]; return [7, "done", [5, [0]]]; } } })((v_double)((24|0), "0123456789abcdef"));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();