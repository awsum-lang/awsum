"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_r2 = __s[1];
          {
            const __s = v_r2;
            switch (__s[0]) {
              case 0: {
                const v_value = __s[1];
                return v_value;
              }
              case 1: {
                const v_value = __s[1];
                return v_value;
              }
            }
          }
        }
        case 1: {
          const v_r2 = __s[1];
          {
            const __s = v_r2;
            switch (__s[0]) {
              case 0: {
                const v_value = __s[1];
                return v_value;
              }
              case 1: {
                const v_value = __s[1];
                return v_value;
              }
            }
          }
        }
      }
    }
}

function main(v__input){
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_18_9 = s[1]; return [0, v__do_e_18_9]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_9 = s[1]; return [0, v__do_e_19_9]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_s2 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_s3 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_s4 = s[1]; return [1, (v_s4 + (v_unwrap)([1, [1, "4"]]))]; } } })([1, (v_s3 + ",")]); } } })([1, (v_s2 + (v_unwrap)([1, [0, "3"]]))]); } } })([1, (v_s1 + ",")]); } } })([1, (v_s0 + (v_unwrap)([0, [1, "2"]]))]); } } })([1, ((v_unwrap)([0, [0, "1"]]) + ",")]));
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