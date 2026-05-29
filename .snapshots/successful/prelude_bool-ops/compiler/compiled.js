"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_showBool = (v_b) => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 1: {
          return "True";
        }
        case 2: {
          return "False";
        }
      }
    }
};

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
};

const v_or = (v_a, v_b) => {
    {
      const __s = v_a;
      switch (__s[0]) {
        case 1: {
          return [1];
        }
        case 2: {
          return v_b;
        }
      }
    }
};

const v_not = (v_b) => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 1: {
          return [2];
        }
        case 2: {
          return [1];
        }
      }
    }
};

const v_and = (v_a, v_b) => {
    {
      const __s = v_a;
      switch (__s[0]) {
        case 1: {
          return v_b;
        }
        case 2: {
          return [2];
        }
      }
    }
};

const v__let_12 = (v_res) => {
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
      }
    }
};

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_s3 = s[1]; return __concat(v_s3, (v_showBool)((v_or)([1], [2]))); } } })(__concat(v_s2, (v_showBool)((v_or)([2], [2])))); } } })(__concat(v_s1, (v_showBool)((v_and)([1], [1])))); } } })(__concat(v_s0, (v_showBool)((v_and)([1], [2])))); } } })(__concat((v_showBool)((v_not)([1])), (v_showBool)((v_not)([2])))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();