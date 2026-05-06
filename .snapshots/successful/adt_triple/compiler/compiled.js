"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

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

function v_showTriple(v_t){
    {
      const __s = v_t;
      switch (__s[0]) {
        case 0: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          return (v_h0)(v_a, v_b, v_c);
        }
      }
    }
}

function main(v__input){
    return (v__let_2)((v_showTriple)([0, "one", "two", "three"]));
}

function v_h0(v_a, v_b, v_c){
    {
      const __s = [1, (v_a + " ")];
      switch (__s[0]) {
        case 0: {
          const v__do_e_19_3 = __s[1];
          return [0, v__do_e_19_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + v_b)];
            switch (__s[0]) {
              case 0: {
                const v__do_e_20_3 = __s[1];
                return [0, v__do_e_20_3];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = [1, (v_s1 + " ")];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_21_3 = __s[1];
                      return [0, v__do_e_21_3];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return [1, (v_s2 + v_c)];
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
}

function v__let_2(v_res){
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