"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_show = (v_m) => {
    {
      const __s = v_m;
      switch (__s[0]) {
        case 10: {
          return [4, "Nothing"];
        }
        case 11: {
          const v_s = __s[1];
          return __concat("Just ", v_s);
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

const v_headList = (v_xs) => {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 12: {
          return [10];
        }
        case 13: {
          const v_h = __s[1];
          const v__t = __s[2];
          return [11, v_h];
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

const v__let_14 = (v_noElems, v_single, v_multi) => {
    return (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_s2 = s[1]; return __concat(v_s2, v_c); } } })(__concat(v_s1, "|")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, "|")); } } })((v_show)(v_multi)); } } })((v_show)(v_single)); } } })((v_show)(v_noElems)));
};

const v__apply__lift_13 = (v__k, v__x) => {
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 14: {
          return v__x;
        }
        case 15: {
          const v__pk_15 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_15;
          const __t1 = (v__k[0] = 13, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
};

const v__cps__lift_13 = (v___input, v__k) => {
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 12: {
          return (v__apply__lift_13)(v__k, [12]);
        }
        case 13: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 15, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
};

const v__lift_13 = (v___input) => {
    return (v__cps__lift_13)(v___input, [14]);
};

const v__let_15 = (v_noElems, v_single) => {
    return (v__let_14)(v_noElems, v_single, (v_headList)([13, "a", [13, "b", [13, "c", (v__lift_13)([12])]]]));
};

const v__let_16 = (v_noElems) => {
    return (v__let_15)(v_noElems, (v_headList)([13, "a", (v__lift_13)([12])]));
};

const main = (v__let_16)((v_headList)((v__lift_13)([12])));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();