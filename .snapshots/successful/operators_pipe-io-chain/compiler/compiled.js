"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

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
        case 3: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

const main = (v__df_andThenIO_0)((v__df_andThenIO_2)((v__lift_8)([2, "a", [0, [0]]])));

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [0]);
}

function v__cps__lift_1(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [0, v___f0]);
        }
        case 1: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [1, v___f0]);
        }
        case 2: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = [1, v__k, v___f0];
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v___f0 = __s[1];
          return (v__apply__lift_1)(v__k, [3, [2, v___f0]]);
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
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [2, v___f0, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__lam_7(v__u){
    return [2, "c", [0, [0]]];
}

function v__lift_8(v___input){
    return (v__cps__lift_8)(v___input, [0]);
}

function v__cps__lift_8(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [0, v___f0]);
        }
        case 1: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [1, v___f0]);
        }
        case 2: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = [1, v__k, v___f0];
          v___input = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v___f0 = __s[1];
          return (v__apply__lift_8)(v__k, [3, [3, v___f0]]);
        }
      }
    }
  }
}

function v__apply__lift_8(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [2, v___f0, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__lam_10(v__u){
    return (v__lift_8)([2, "b", [0, [0]]]);
}

function v__df_andThenIO_0(v_io){
    return (v__cps__df_andThenIO_0)(v_io, [0]);
}

function v__cps__df_andThenIO_0(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, (v__lift_1)((v__lam_7)(v_a)));
        }
        case 1: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [1, v_e]);
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = [1, v__k, v_s];
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_0)(v__k, [3, [0, v_cont]]);
        }
      }
    }
  }
}

function v__apply__df_andThenIO_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [2, v_s, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__df_andThenIO_2(v_io){
    return (v__cps__df_andThenIO_2)(v_io, [0]);
}

function v__cps__df_andThenIO_2(v_io, v__k){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, (v__lift_1)((v__lam_10)(v_a)));
        }
        case 1: {
          const v_e = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [1, v_e]);
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          const __t0 = v_next;
          const __t1 = [1, v__k, v_s];
          v_io = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v_cont = __s[1];
          return (v__apply__df_andThenIO_2)(v__k, [3, [1, v_cont]]);
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
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_s = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [2, v_s, v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9(v__args){
    return (v__cps__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9)(v__args, [0]);
}

function v__cps__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v__cl = __s[1];
          const v__arg0 = __s[2];
          {
            const __s = v__cl;
            switch (__s[0]) {
              case 0: {
                const v__cap0_0 = __s[1];
                const __t0 = [1, v__cap0_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                const v__cap1_0 = __s[1];
                const __t0 = [2, v__cap1_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 2: {
                const v__cap2_0 = __s[1];
                const __t0 = [3, v__cap2_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 3: {
                const v__cap3_0 = __s[1];
                const __t0 = [4, v__cap3_0, v__arg0];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
        case 1: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = [0, v_cont, v_result];
          const __t1 = [1, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 2: {
          const v_cont = __s[1];
          const v_result = __s[2];
          const __t0 = [0, v_cont, v_result];
          const __t1 = [2, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 3: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = [0, v___f, v___arg];
          const __t1 = [3, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
        case 4: {
          const v___f = __s[1];
          const v___arg = __s[2];
          const __t0 = [0, v___f, v___arg];
          const __t1 = [4, v__k];
          v__args = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const __t0 = v__pk_1;
          const __t1 = (v__df_andThenIO_0)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 2: {
          const v__pk_2 = __s[1];
          const __t0 = v__pk_2;
          const __t1 = (v__df_andThenIO_2)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 3: {
          const v__pk_3 = __s[1];
          const __t0 = v__pk_3;
          const __t1 = (v__lift_1)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
        case 4: {
          const v__pk_4 = __s[1];
          const __t0 = v__pk_4;
          const __t1 = (v__lift_8)(v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply1(v__cl, v__arg0){
    return (v__scc__apply1__df__lam_3_1__df__lam_3_3__lift_2__lift_9)([0, v__cl, v__arg0]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();