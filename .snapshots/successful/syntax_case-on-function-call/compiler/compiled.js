"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }

const v_search = (v_key) => {
    {
      const __s = __concat("found:", v_key);
      switch (__s[0]) {
        case 3: {
          const v__do_e_0 = __s[1];
          return [3, v__do_e_0];
        }
        case 4: {
          const v_found = __s[1];
          return [4, [22, v_found]];
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

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v_e = s[1]; return [3, v_e]; } case 4: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 22: { const v_v = s[1]; return [4, v_v]; } } })(v___p0); } } })((v_search)("hello")));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();