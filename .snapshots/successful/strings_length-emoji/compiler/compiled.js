"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }
function __eqUInt32(a, b){ return a === b ? [0] : [1]; }
function __lengthCodePoints(s){ let n = 0; for (const _ of s) n++; return (n >>> 0); }
function __lengthUtf16CodeUnits(s){ return (s.length >>> 0); }
function __lengthBytesAsUtf8(s){ return (new TextEncoder().encode(s).length >>> 0); }

function v_check(v_expected, v_actual, v_label){
    {
      const __s = __eqUInt32(v_expected, v_actual);
      switch (__s[0]) {
        case 0: {
          return [1, (v_label + "=ok")];
        }
        case 1: {
          {
            const __s = [1, (v_label + "=FAIL(expected=")];
            switch (__s[0]) {
              case 0: {
                const v__do_e_12_5 = __s[1];
                return [0, v__do_e_12_5];
              }
              case 1: {
                const v_s0 = __s[1];
                {
                  const __s = [1, (v_s0 + String(v_expected))];
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_13_5 = __s[1];
                      return [0, v__do_e_13_5];
                    }
                    case 1: {
                      const v_s1 = __s[1];
                      {
                        const __s = [1, (v_s1 + ", got=")];
                        switch (__s[0]) {
                          case 0: {
                            const v__do_e_14_5 = __s[1];
                            return [0, v__do_e_14_5];
                          }
                          case 1: {
                            const v_s2 = __s[1];
                            {
                              const __s = [1, (v_s2 + String(v_actual))];
                              switch (__s[0]) {
                                case 0: {
                                  const v__do_e_15_5 = __s[1];
                                  return [0, v__do_e_15_5];
                                }
                                case 1: {
                                  const v_s3 = __s[1];
                                  return [1, (v_s3 + ")")];
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
            }
          }
        }
      }
    }
}

const v_run = ((s) => { switch(s[0]) { case 0: { const v__do_e_20_3 = s[1]; return [0, v__do_e_20_3]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_3 = s[1]; return [0, v__do_e_21_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_3 = s[1]; return [0, v__do_e_22_3]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_3 = s[1]; return [0, v__do_e_23_3]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_3 = s[1]; return [0, v__do_e_24_3]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_3 = s[1]; return [0, v__do_e_25_3]; } case 1: { const v_s2 = s[1]; return [1, (v_s2 + v_c)]; } } })([1, (v_s1 + ", ")]); } } })([1, (v_s0 + v_b)]); } } })([1, (v_a + ", ")]); } } })((v_check)((4 >>> 0), __lengthBytesAsUtf8("🔥"), "lengthBytesAsUtf8")); } } })((v_check)((2 >>> 0), __lengthUtf16CodeUnits("🔥"), "lengthUtf16CodeUnits")); } } })((v_check)((1 >>> 0), __lengthCodePoints("🔥"), "lengthCodePoints"));

function main(v__input){
    {
      const __s = v_run;
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