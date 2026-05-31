"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [18]] : [4, a + b]; }
function __splitOnFirst(sep, str){ const i = str.indexOf(sep); if (i < 0) return [10]; return [11, [14, str.substring(0, i), str.substring(i + sep.length)]]; }

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

const v_renderTuple = (v_a, v_b) => {
    {
      const __s = __concat("Just(", v_a);
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_s0 = __s[1];
          {
            const __s = __concat(v_s0, "|");
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                return [3, v__do_e_1];
              }
              case 4: {
                const v_s1 = __s[1];
                {
                  const __s = __concat(v_s1, v_b);
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

const v_render = (v_r) => {
    {
      const __s = v_r;
      switch (__s[0]) {
        case 10: {
          return [4, "Nothing"];
        }
        case 11: {
          const v_t = __s[1];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 14: {
                const v_a = __s[1];
                const v_b = __s[2];
                return (v_renderTuple)(v_a, v_b);
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

const main = (v__let_12)(((s) => { switch(s[0]) { case 3: { const v__do_e_23 = s[1]; return [3, v__do_e_23]; } case 4: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_22 = s[1]; return [3, v__do_e_22]; } case 4: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_21 = s[1]; return [3, v__do_e_21]; } case 4: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_20 = s[1]; return [3, v__do_e_20]; } case 4: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_19 = s[1]; return [3, v__do_e_19]; } case 4: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_18 = s[1]; return [3, v__do_e_18]; } case 4: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_17 = s[1]; return [3, v__do_e_17]; } case 4: { const v_g = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_16 = s[1]; return [3, v__do_e_16]; } case 4: { const v_h = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_15 = s[1]; return [3, v__do_e_15]; } case 4: { const v_r0 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_14 = s[1]; return [3, v__do_e_14]; } case 4: { const v_r1 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_13 = s[1]; return [3, v__do_e_13]; } case 4: { const v_r2 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_12 = s[1]; return [3, v__do_e_12]; } case 4: { const v_r3 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_11 = s[1]; return [3, v__do_e_11]; } case 4: { const v_r4 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_10 = s[1]; return [3, v__do_e_10]; } case 4: { const v_r5 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_9 = s[1]; return [3, v__do_e_9]; } case 4: { const v_r6 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_8 = s[1]; return [3, v__do_e_8]; } case 4: { const v_r7 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_7 = s[1]; return [3, v__do_e_7]; } case 4: { const v_r8 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_6 = s[1]; return [3, v__do_e_6]; } case 4: { const v_r9 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_5 = s[1]; return [3, v__do_e_5]; } case 4: { const v_r10 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_4 = s[1]; return [3, v__do_e_4]; } case 4: { const v_r11 = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_3 = s[1]; return [3, v__do_e_3]; } case 4: { const v_r12 = s[1]; return __concat(v_r12, v_h); } } })(__concat(v_r11, ", ")); } } })(__concat(v_r10, v_g)); } } })(__concat(v_r9, ", ")); } } })(__concat(v_r8, v_f)); } } })(__concat(v_r7, ", ")); } } })(__concat(v_r6, v_e)); } } })(__concat(v_r5, ", ")); } } })(__concat(v_r4, v_d)); } } })(__concat(v_r3, ", ")); } } })(__concat(v_r2, v_c)); } } })(__concat(v_r1, ", ")); } } })(__concat(v_r0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_render)(__splitOnFirst("abcde", "ab"))); } } })((v_render)(__splitOnFirst("abc", "abc"))); } } })((v_render)(__splitOnFirst(":", "foo:"))); } } })((v_render)(__splitOnFirst(":", ":foo"))); } } })((v_render)(__splitOnFirst("", "abc"))); } } })((v_render)(__splitOnFirst("x", "abc"))); } } })((v_render)(__splitOnFirst("::", "user::42::admin"))); } } })((v_render)(__splitOnFirst(",", "a,b,c"))));

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();