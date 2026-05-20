"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }

function v_pureEither(v_x){
    return [4, v_x];
}

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

const v_inc42 = (v__df_apply_0)((42|0));

const v_op1 = [4, (1|0)];

function v_op2WithA(v_n){
    return [4, v_n];
}

const v_g = ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, [2252990199, v__do_e_1]]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, [2269767818, v__do_e_0]]; } case 4: { const v_b = s[1]; return (v_pureEither)(v_b); } } })((v_op2WithA)(v_a)); } } })(v_op1);

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 2252990199: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 20: {
                      return [4, "ErrA"];
                    }
                  }
                }
              }
              case 2269767818: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 21: {
                      return [4, "ErrB"];
                    }
                  }
                }
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return __concat("Ok ", String(v_n));
        }
      }
    }
}

const main = (v__let_13)(((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s0 = s[1]; return __concat(v_s0, v_d); } } })(__concat(String(v_inc42), " / ")); } } })((v_describe)(v_g)));

function v__lam_12(v_n){
    return v_n;
}

function v__let_13(v_res){
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

function v__df_apply_0(v_x){
    return (v__lam_12)(v_x);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();