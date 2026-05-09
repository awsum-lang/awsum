"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __addInt32(a, b){ const s = a + b; if (s > 2147483647) return [3, [882564211, [14]]]; if (s < -2147483648) return [3, [3768445577, [13]]]; return [4, s|0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [3, [589989748, [15]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [3, [502975519, [16]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [3, [502975519, [16]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [3, [502975519, [16]]]; } return [4, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

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
                v_io = __t0;
                continue;
              }
            }
          }
        }
        case 8: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

function v_opTuple(v__wild0){
    return [4, [12, (1|0), (2|0), (3|0)]];
}

function v_processInput(v_raw){
    return (v__let_7)(((s) => { switch(s[0]) { case 3: { const v__do_e_11_9 = s[1]; return [3, v__do_e_11_9]; } case 4: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 12: { const v_a = s[1]; const v_b = s[2]; const v_c = s[3]; return (v_pureEither)(((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return v_c; } case 4: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return v_c; } case 4: { const v_abc = s[1]; return v_abc; } } })(__addInt32(v_ab, v_c)); } } })(__addInt32(v_a, v_b))); } } })(v___p0); } } })((v_opTuple)(v_raw)));
}

function v_handleInputErr(v_e){
    {
      const __s = v_e;
      switch (__s[0]) {
        case 502975519: {
          const v__u = __s[1];
          return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
        }
        case 589989748: {
          const v__l = __s[1];
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
}

const main = (v__df_handleErrorIO_0)((v__df_andThenIO_2)([8, [15]]));

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [21]);
}

function v__cps__lift_1(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 5: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [5, v___f0]);
        }
        case 6: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [6, v___f0]);
        }
        case 7: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = [22, v__k, v___f0];
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [8, [16, v___f0]]);
        }
      }
    }
  }
}

function v__apply__lift_1(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 21: {
          return v__x;
        }
        case 22: {
          const v__pk_22 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_22;
          const __t1 = [7, v___f0, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__let_7(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 3: {
          const v___w0 = __s[1];
          return [7, "PARSE_ERROR", [5, [0]]];
        }
        case 4: {
          const v_n = __s[1];
          return [7, String(v_n), [5, [0]]];
        }
      }
    }
}

function v__io_getargs_cont(v_result){
    {
      const __s = v_result;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [6, v_e];
        }
        case 4: {
          const v_s = __s[1];
          return [5, v_s];
        }
      }
    }
}

function v__df_handleErrorIO_0(v_io){
    return (v__cps__df_handleErrorIO_0)(v_io, [23]);
}

function v__cps__df_handleErrorIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [5, v_a]);
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, (v_handleInputErr)(v_e));
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = [24, v__k, v_s];
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_handleErrorIO_0)(v__k, [8, [14, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_handleErrorIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_24;
          const __t1 = [7, v_s, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__df_andThenIO_2(v_io){
    return (v__cps__df_andThenIO_2)(v_io, [25]);
}

function v__cps__df_andThenIO_2(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 5: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, (v__lift_1)((v_processInput)(v_a)));
        }
        case 6: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [6, v_e]);
        }
        case 7: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = [26, v__k, v_s];
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 8: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [8, [13, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_andThenIO_2(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_26;
          const __t1 = [7, v_s, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__args){
    return (v__cps__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)(v__args, [27]);
}

function v__cps__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 17: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 13: {
                const v__cap13_0 = __s[1];
                const __t0 = [18, v__cap13_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 14: {
                const v__cap14_0 = __s[1];
                const __t0 = [19, v__cap14_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 15: {
                return (v__apply__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)(v__k, (v__io_getargs_cont)(v__arg0));
              }
              case 16: {
                const v__cap16_0 = __s[1];
                const __t0 = [20, v__cap16_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 18: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = [17, v_cont, v_result];
          const __t1 = [28, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 19: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = [17, v_cont, v_result];
          const __t1 = [29, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 20: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = [17, v___f, v___arg];
          const __t1 = [30, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = __s[1];
          const __t0 = v__pk_28;
          const __t1 = (v__df_andThenIO_2)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 29: {
          const v__pk_29 = __s[1];
          const __t0 = v__pk_29;
          const __t1 = (v__df_handleErrorIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 30: {
          const v__pk_30 = __s[1];
          const __t0 = v__pk_30;
          const __t1 = (v__lift_1)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_3_3__df__lam_6_1__lift_2)([17, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();