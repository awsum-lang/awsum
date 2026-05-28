"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_show = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 22: {
                return [4, "Left Missing"];
              }
            }
          }
        }
        case 4: {
          const v_s = __s[1];
          return __concat("Right ", v_s);
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

const v_nothingAsLeft = (v_e, v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 10: {
          return [3, v_e];
        }
        case 11: {
          const v_a = __s[1];
          return [4, v_a];
        }
      }
    }
};

const v__lift_14 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 10: {
          return [10];
        }
        case 11: {
          const v___f0 = __s[1];
          return [11, v___f0];
        }
      }
    }
};

const v__let_12 = (v_msg) => {
    {
      const __s = v_msg;
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

const v__let_13 = (v_fromNothing, v_fromJust) => {
    return (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_sep = s[1]; return __concat(v_sep, v_b); } } })(__concat(v_a, "|")); } } })((v_show)(v_fromJust)); } } })((v_show)(v_fromNothing)));
};

const v__let_15 = (v_fromNothing) => {
    return (v__let_13)(v_fromNothing, (v_nothingAsLeft)([22], [11, "hi"]));
};

const main = (v__let_15)((v_nothingAsLeft)([22], (v__lift_14)([10])));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();