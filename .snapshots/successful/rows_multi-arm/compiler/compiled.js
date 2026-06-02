"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [19]] : [4, a + b]; }

const v_showUnit = (v__wild0) => {
    return "Unit";
};

const v_whatsInside = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 11: {
          return [4, "Nothing"];
        }
        case 12: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 796142685: {
                const v_b = __s[1];
                {
                  const __s = v_b;
                  switch (__s[0]) {
                    case 1: {
                      return [4, "Just True"];
                    }
                    case 2: {
                      return [4, "Just False"];
                    }
                  }
                }
              }
              case 1759602215: {
                const v_u = __s[1];
                return __concat("Just ", (v_showUnit)(v_u));
              }
            }
          }
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

const v__lift_25 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, v___f0];
        }
      }
    }
};

const v__lift_24 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, [1759602215, v___f0]];
        }
      }
    }
};

const v__lift_23 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 11: {
          return [11];
        }
        case 12: {
          const v___f0 = __s[1];
          return [12, [796142685, v___f0]];
        }
      }
    }
};

const v_summary = ((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_2 = s[1]; return [3, v__do_e_2]; } case 4: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_1 = s[1]; return [3, v__do_e_1]; } case 4: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_s2 = s[1]; return __concat(v_s2, v_c); } } })(__concat(v_s1, "; ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, "; ")); } } })((v_whatsInside)((v__lift_25)([11]))); } } })((v_whatsInside)((v__lift_24)([12, [0]]))); } } })((v_whatsInside)((v__lift_23)([12, [1]])));

const v__let_26 = (v_res) => {
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

const main = (v__let_26)(v_summary);

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();