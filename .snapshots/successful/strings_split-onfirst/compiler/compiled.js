"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __splitOnFirst(sep, str){ const i = str.indexOf(sep); if (i < 0) return [0]; return [1, [0, str.substring(0, i), str.substring(i + sep.length)]]; }

function v_render(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          return [1, "Nothing"];
        }
        case 1: {
          const v_t = __s[1];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 0: {
                const v_a = __s[1];
                const v_b = __s[2];
                return (v_renderTuple)(v_a, v_b);
              }
            }
          }
        }
      }
    }
}

function v_renderTuple(v_a, v_b){
    {
      const __s = [1, ("Just(" + v_a)];
      switch (__s[0]) {
        case 0: {
          const v__do_e_12_3 = __s[1];
          return [0, v__do_e_12_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + "|")];
            switch (__s[0]) {
              case 0: {
                const v__do_e_13_3 = __s[1];
                return [0, v__do_e_13_3];
              }
              case 1: {
                const v_s1 = __s[1];
                {
                  const __s = [1, (v_s1 + v_b)];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_14_3 = __s[1];
                      return [0, v__do_e_14_3];
                    }
                    case 1: {
                      const v_s2 = __s[1];
                      return [1, (v_s2 + ")")];
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

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_e = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_9 = s[1]; return [0, v__do_e_25_9]; } case 1: { const v_f = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_9 = s[1]; return [0, v__do_e_26_9]; } case 1: { const v_g = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_9 = s[1]; return [0, v__do_e_27_9]; } case 1: { const v_h = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_r0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_29_9 = s[1]; return [0, v__do_e_29_9]; } case 1: { const v_r1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_30_9 = s[1]; return [0, v__do_e_30_9]; } case 1: { const v_r2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_31_9 = s[1]; return [0, v__do_e_31_9]; } case 1: { const v_r3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_32_9 = s[1]; return [0, v__do_e_32_9]; } case 1: { const v_r4 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_33_9 = s[1]; return [0, v__do_e_33_9]; } case 1: { const v_r5 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_34_9 = s[1]; return [0, v__do_e_34_9]; } case 1: { const v_r6 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_35_9 = s[1]; return [0, v__do_e_35_9]; } case 1: { const v_r7 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_36_9 = s[1]; return [0, v__do_e_36_9]; } case 1: { const v_r8 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_37_9 = s[1]; return [0, v__do_e_37_9]; } case 1: { const v_r9 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_38_9 = s[1]; return [0, v__do_e_38_9]; } case 1: { const v_r10 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_39_9 = s[1]; return [0, v__do_e_39_9]; } case 1: { const v_r11 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_40_9 = s[1]; return [0, v__do_e_40_9]; } case 1: { const v_r12 = s[1]; return [1, (v_r12 + v_h)]; } } })([1, (v_r11 + ", ")]); } } })([1, (v_r10 + v_g)]); } } })([1, (v_r9 + ", ")]); } } })([1, (v_r8 + v_f)]); } } })([1, (v_r7 + ", ")]); } } })([1, (v_r6 + v_e)]); } } })([1, (v_r5 + ", ")]); } } })([1, (v_r4 + v_d)]); } } })([1, (v_r3 + ", ")]); } } })([1, (v_r2 + v_c)]); } } })([1, (v_r1 + ", ")]); } } })([1, (v_r0 + v_b)]); } } })([1, (v_a + ", ")]); } } })((v_render)(__splitOnFirst("abcde", "ab"))); } } })((v_render)(__splitOnFirst("abc", "abc"))); } } })((v_render)(__splitOnFirst(":", "foo:"))); } } })((v_render)(__splitOnFirst(":", ":foo"))); } } })((v_render)(__splitOnFirst("", "abc"))); } } })((v_render)(__splitOnFirst("x", "abc"))); } } })((v_render)(__splitOnFirst("::", "user::42::admin"))); } } })((v_render)(__splitOnFirst(",", "a,b,c"))));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();