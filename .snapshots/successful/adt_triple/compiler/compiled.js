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

const v_h0 = (v_a, v_b, v_c) => {
    {
      const __s = __concat(v_a, " ");
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, v_b);
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                return [3, v__do_e_1];
              }
              case 4: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, " ");
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_0 = __s[1];
                      return [3, v__do_e_0];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      return __concat(v_s2, v_c);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
};

const v_showTriple = (v_t) => {
    {
      const __s = v_t;
      switch (__s[0]) {
        case 22: {
          const v_a = __s[1];
          const v_b = __s[2];
          const v_c = __s[3];
          return (v_h0)(v_a, v_b, v_c);
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

const main = (v__let_12)((v_showTriple)([22, "one", "two", "three"]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();