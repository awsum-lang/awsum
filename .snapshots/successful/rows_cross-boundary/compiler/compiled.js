"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
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

const v_defaultJust = [10, [1]];

const v_defaultBools = [21, [1], [21, [2], (v__lift_7)([20])]];

const v_defaultRight = [4, [10, [2]]];

function v_dispatchInner(v_x){
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
}

function v_describeMaybe(v_m){
    {
      const __s = v_m;
      switch (__s[0]) {
        case 9: {
          return [4, "N"];
        }
        case 10: {
          const v_inner = __s[1];
          return __concat("J", (v_dispatchInner)(v_inner));
        }
      }
    }
}

function v_describeLst(v_xs){
    return (v__cps_describeLst)(v_xs, [22]);
}

function v__cps_describeLst(v_xs, v__k){
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 20: {
          return (v__apply_describeLst)(v__k, [4, ""]);
        }
        case 21: {
          const v_h = __s[1];
          const v_t = __s[2];
          const __t0 = v_t;
          const __t1 = (v_xs[0] = 23, v_xs[1] = v__k, v_xs[2] = v_h, v_xs);
          v__k = null;
          v_xs = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply_describeLst(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = __s[1];
          const v_h = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 3: {
                const v__do_e_35_5 = __s[1];
                const __t0 = v__pk_23;
                const __t1 = (v__x[0] = 3, v__x[1] = v__do_e_35_5, v__x);
                v__k = null;
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 4: {
                const v_rest = __s[1];
                const __t0 = v__pk_23;
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
}

function v_describeEither(v_r){
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
}

const v_summary = ((s) => { switch(s[0]) { case 3: { const v__do_e_45_3 = s[1]; return [3, v__do_e_45_3]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_46_3 = s[1]; return [3, v__do_e_46_3]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_47_3 = s[1]; return [3, v__do_e_47_3]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_48_3 = s[1]; return [3, v__do_e_48_3]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_49_3 = s[1]; return [3, v__do_e_49_3]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_50_3 = s[1]; return [3, v__do_e_50_3]; } case 4: { const v_s2 = s[1]; return __concat(v_s2, v_c); } } })(__concat(v_s1, " / ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, " / ")); } } })((v_describeEither)((v__lift_10)(v_defaultRight))); } } })((v_describeLst)((v__lift_9)(v_defaultBools))); } } })((v_describeMaybe)((v__lift_8)(v_defaultJust)));

const main = (v__let_11)(v_summary);

function v__lift_7(v___input){
    return (v__cps__lift_7)(v___input, [24]);
}

function v__cps__lift_7(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 20: {
          return (v__apply__lift_7)(v__k, [20]);
        }
        case 21: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 25, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__lift_7(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 24: {
          return v__x;
        }
        case 25: {
          const v__pk_25 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_25;
          const __t1 = (v__k[0] = 21, v__k[1] = v___f0, v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__lift_8(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 9: {
          return [9];
        }
        case 10: {
          const v___f0 = __s[1];
          return [10, [796142685, v___f0]];
        }
      }
    }
}

function v__lift_9(v___input){
    return (v__cps__lift_9)(v___input, [26]);
}

function v__cps__lift_9(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 20: {
          return (v__apply__lift_9)(v__k, [20]);
        }
        case 21: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = (v___input[0] = 27, v___input[1] = v__k, v___input[2] = v___f0, v___input);
          v__k = null;
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__lift_9(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_27;
          const __t1 = (v__k[0] = 21, v__k[1] = [796142685, v___f0], v__k[2] = v__x, v__k);
          v__x = null;
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__lift_10(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, v___f0];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, (v__lift_8)(v___f0)];
        }
      }
    }
}

function v__let_11(v_res){
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
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();