"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function main(v_inputArg){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_7_9 = s[1]; return [0, v__do_e_7_9]; } case 1: { const v_input = s[1]; return (v__lift_1)((v_addGreeting)(v_input)); } } })(v_inputArg));
}

const v_greeting = "Hello";

function v_addGreeting(v_name){
    {
      const __s = [1, (v_greeting + ", ")];
      switch (__s[0]) {
        case 0: {
          const v__do_e_22_3 = __s[1];
          return [0, v__do_e_22_3];
        }
        case 1: {
          const v_s0 = __s[1];
          {
            const __s = [1, (v_s0 + v_name)];
            switch (__s[0]) {
              case 0: {
                const v__do_e_23_3 = __s[1];
                return [0, v__do_e_23_3];
              }
              case 1: {
                const v_s1 = __s[1];
                return [1, (v_s1 + "!")];
              }
            }
          }
        }
      }
    }
}

function v__lift_1(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          const v___f0 = __s[1];
          return [0, [589989748, v___f0]];
        }
        case 1: {
          const v___f0 = __s[1];
          return [1, v___f0];
        }
      }
    }
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v_e = __s[1];
          {
            const __s = v_e;
            switch (__s[0]) {
              case 502975519: {
                const v___rw = __s[1];
                return __print("UNPAIRED_UTF16_SURROGATE");
              }
              case 589989748: {
                const v___rw = __s[1];
                return __print("STRING_TOO_LONG");
              }
            }
          }
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