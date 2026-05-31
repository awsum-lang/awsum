"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }
function __predUInt32(x){ return x === 0 ? [3, [16]] : [4, ((x - 1) >>> 0)]; }
function __eqUInt32(a, b){ return a === b ? [1] : [2]; }
function __lengthUtf16CodeUnits(s){ return (s.length >>> 0); }

const v_runIO = (v_io) => {
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
                v_io = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v_maxStringLengthUtf16CodeUnits = (134217728 >>> 0);

const v_block = "你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界你好世界";

const v__lift_16 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v__lift_0 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
};

const v__apply__scc__df_andThenEither_0__lam_15_build = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 11: {
          return v__x;
        }
        case 12: {
          const v__pk_12 = __s[1];
          const __t0 = v__pk_12;
          const __t1 = (v__lift_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__scc__df_andThenEither_0__lam_15_build = (v__args, v__k) => {
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 8: {
          const v_x = __s[1];
          const v__df_andThenEither_0_cap0_0 = __s[2];
          {
            const __s = v_x;
            switch (__s[0]) {
              case 3: {
                const v_e = __s[1];
                return (v__apply__scc__df_andThenEither_0__lam_15_build)(v__k, [3, v_e]);
              }
              case 4: {
                const v_a = __s[1];
                const __t0 = (v__args[0] = 9, v__args[1] = v__df_andThenEither_0_cap0_0, v__args[2] = v_a, v__args);
                const __t1 = [12, v__k];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 9: {
          const v_m = __s[1];
          const v_doubled = __s[2];
          const __t0 = (v__args[0] = 10, v__args[1] = v_m, v__args[2] = v_doubled, v__args);
          const __t1 = v__k;
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 10: {
          const v_n = __s[1];
          const v_acc = __s[2];
          {
            const __s = __predUInt32(v_n);
            switch (__s[0]) {
              case 3: {
                const v___w0 = __s[1];
                return (v__apply__scc__df_andThenEither_0__lam_15_build)(v__k, [4, v_acc]);
              }
              case 4: {
                const v_m = __s[1];
                const __t0 = (v__args[0] = 8, v__args[1] = (v__lift_16)(__concat(v_acc, v_acc)), v__args[2] = v_m, v__args);
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
};

const v__scc__df_andThenEither_0__lam_15_build = (v__args) => {
    return (v__cps__scc__df_andThenEither_0__lam_15_build)(v__args, [11]);
};

const v_build = (v_n, v_acc) => {
    return (v__scc__df_andThenEither_0__lam_15_build)([10, v_n, v_acc]);
};

const v_runTest = ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return "FAIL: build returned Left at the cap"; } case 4: { const v_capStr = s[1]; return ((s) => { switch(s[0]) { case 1: { return ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return "OK"; } case 4: { const v___w0 = s[1]; return "FAIL: cap + 1 returned Right"; } } })(__concat(v_capStr, "!")); } case 2: { return "FAIL: built string length is not at cap"; } } })(__eqUInt32(__lengthUtf16CodeUnits(v_capStr), v_maxStringLengthUtf16CodeUnits)); } } })((v_build)((20 >>> 0), v_block));

const main = [7, v_runTest, [5, [0]]];

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();