"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }

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
      }
    }
  }
}

function v_opA(v_n){
    return [1, v_n];
}

function v_opB(v__n){
    return [0, [0]];
}

function v_run(v_x){
    {
      const __s = (v_opA)(v_x);
      switch (__s[0]) {
        case 0: {
          const v__do_e_19_3 = __s[1];
          return [0, [2252990199, v__do_e_19_3]];
        }
        case 1: {
          const v_a = __s[1];
          return (v__lift_2)((v_opB)(v_a));
        }
      }
    }
}

function v_describe(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 2252990199: {
                const v___rw = __s[1];
                return [1, "ErrA"];
              }
              case 2269767818: {
                const v___rw = __s[1];
                return [1, "ErrB"];
              }
            }
          }
        }
        case 1: {
          const v_n = __s[1];
          return __concat("Ok ", String(v_n));
        }
      }
    }
}

function main(v__input){
    return (v__let_3)((v_describe)((v_run)((5|0))));
}

function v__lift_2(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          const v___f0 = __s[1];
          return [0, [2269767818, v___f0]];
        }
        case 1: {
          const v___f0 = __s[1];
          return [1, v___f0];
        }
      }
    }
}

function v__let_3(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();