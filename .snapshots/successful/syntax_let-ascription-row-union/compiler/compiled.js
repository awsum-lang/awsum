"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

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

const v_pureEither = (v_x) => {
    return [4, v_x];
};

const v_opB = [4, (2|0)];

const v_opA = [4, (1|0)];

const v__let_15 = (v_res) => {
    {
      const __s = v_res;
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
                    case 22: {
                      return [7, "ERR_A", [5, [0]]];
                    }
                  }
                }
              }
              case 2269767818: {
                const v___rw = __s[1];
                {
                  const __s = v___rw;
                  switch (__s[0]) {
                    case 23: {
                      return [7, "ERR_B", [5, [0]]];
                    }
                  }
                }
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return [7, String(v_n), [5, [0]]];
        }
      }
    }
};

const main = (v__let_15)(((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, [2252990199, v__do_e_1]]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, [2269767818, v__do_e_0]]; } case 4: { const v_b = s[1]; return (v_pureEither)(v_b); } } })(v_opB); } } })(v_opA));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();