"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }

const v_showPairBody = (v_first, v_second) => {
    {
      const __s = __concat("(", v_first);
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, ", ");
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                return [3, v__do_e_1];
              }
              case 4: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, v_second);
                  switch (__s[0]) {
                    case 3: {
                      const v__do_e_0 = __s[1];
                      return [3, v__do_e_0];
                    }
                    case 4: {
                      const v_s2 = __s[1];
                      return __concat(v_s2, ")");
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

const v_showPair = (v_pair) => {
    {
      const __s = v_pair;
      switch (__s[0]) {
        case 20: {
          const v_first = __s[1];
          const v_second = __s[2];
          return (v_showPairBody)(v_first, v_second);
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

const main = (v__let_12)((v_showPair)([20, "hello", "world"]));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();