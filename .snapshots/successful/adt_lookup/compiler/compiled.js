"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_unwrap = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 22: {
          const v_value = __s[1];
          return v_value;
        }
        case 23: {
          return "not found";
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

const v__lift_15 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 22: {
          const v___f0 = __s[1];
          return [22, v___f0];
        }
        case 23: {
          return [23];
        }
      }
    }
};

const v__let_16 = (v_res) => {
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

const main = (v__let_16)(((s) => { switch(s[0]) { case 3: { const v__do_e_0 = s[1]; return [3, v__do_e_0]; } case 4: { const v_s0 = s[1]; return __concat(v_s0, (v_unwrap)((v__lift_15)([23]))); } } })(__concat((v_unwrap)([22, "hello"]), ", ")));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();