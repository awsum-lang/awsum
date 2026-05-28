"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

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

const v_dispatchInner = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 796142685: {
          const v_b = __s[1];
          {
            const __s = v_b;
            switch (__s[0]) {
              case 1: {
                return "T";
              }
              case 2: {
                return "F";
              }
            }
          }
        }
      }
    }
};

const v_describeMaybe = (v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 10: {
          return [4, "N"];
        }
        case 11: {
          const v_inner = __s[1];
          return __concat("J", (v_dispatchInner)(v_inner));
        }
      }
    }
};

const v_describeEither = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return [4, "ErrA"];
        }
        case 4: {
          const v_m = __s[1];
          return (v_describeMaybe)(v_m);
        }
      }
    }
};

const v_defaultRight = [4, [11, [2]]];

const v_defaultJust = [11, [1]];

const v__lift_13 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 10: {
          return [10];
        }
        case 11: {
          const v___f0 = __s[1];
          return [11, [796142685, v___f0]];
        }
      }
    }
};

const v__lift_15 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, (v__lift_13)(v___f0)];
        }
      }
    }
};

const v__let_16 = (v_res) => {
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

const v__apply_describeLst = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = __s[1];
          const v_h = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                const __t0 = v__pk_26;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_0, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_26;
                const __t1 = __concat((v_dispatchInner)(v_h), v_rest);
                v__x = null;
                v__k = null;
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
};

const v__cps_describeLst = (v_xs, v__k) => {
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 23: {
          return (v__apply_describeLst)(v__k, [4, ""]);
        }
        case 24: {
          const v_h = __s[1];
          const v_t = __s[2];
          const __t0 = v_t;
          const __t1 = (v_xs[0] = 26, v_xs[1] = v__k, v_xs[2] = v_h, v_xs);
          v__k = null;
          v_xs = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v_describeLst = (v_xs) => {
    return (v__cps_describeLst)(v_xs, [25]);
};

const v__apply__lift_14 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_30;
          const __t1 = (v__k[0] = 24, v__k[1] = [796142685, v___f0], v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_14 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 23: {
          return (v__apply__lift_14)(v__k, [23]);
        }
        case 24: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 30, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_14 = (v___input) => {
    return (v__cps__lift_14)(v___input, [29]);
};

const v__apply__lift_12 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_28;
          const __t1 = (v__k[0] = 24, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_12 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 23: {
          return (v__apply__lift_12)(v__k, [23]);
        }
        case 24: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 28, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_12 = (v___input) => {
    return (v__cps__lift_12)(v___input, [27]);
};

const v_defaultBools = [24, [1], [24, [2], (v__lift_12)([23])]];

const v_summary = ((s) => { switch(s[0]) { case 3: { const v__do_e_6 = s[1]; return [3, v__do_e_6]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_s2 = s[1]; return __concat(v_s2, v_c); } } })(__concat(v_s1, " / ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, " / ")); } } })((v_describeEither)((v__lift_15)(v_defaultRight))); } } })((v_describeLst)((v__lift_14)(v_defaultBools))); } } })((v_describeMaybe)((v__lift_13)(v_defaultJust)));

const main = (v__let_16)(v_summary);

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();