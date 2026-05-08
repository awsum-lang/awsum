"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __eqUInt32(a, b){ return a === b ? [0] : [1]; }
function __lengthCodePoints(s){ let n = 0; for (const _ of s) n++; return (n >>> 0); }
function __lengthUtf16CodeUnits(s){ return (s.length >>> 0); }
function __lengthUtf8Bytes(s){ return (new TextEncoder().encode(s).length >>> 0); }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
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
}

function v_check(v_expected, v_actual, v_label){
    {
      const __s = __eqUInt32(v_expected, v_actual);
      switch (__s[0]) {
        case 0: {
          return __concat(v_label, "=ok");
        }
        case 1: {
          {
            const __s = __concat(v_label, "=FAIL(expected=");
            switch (__s[0]) {
              case 0: {
                const v__do_e_12_5 = __s[1];
                return [0, v__do_e_12_5];
              }
              case 1: {
                const v_s0 = __s[1];
                {
                  const __s = __concat(v_s0, String(v_expected));
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_13_5 = __s[1];
                      return [0, v__do_e_13_5];
                    }
                    case 1: {
                      const v_s1 = __s[1];
                      {
                        const __s = __concat(v_s1, ", got=");
                        switch (__s[0]) {
                          case 0: {
                            const v__do_e_14_5 = __s[1];
                            return [0, v__do_e_14_5];
                          }
                          case 1: {
                            const v_s2 = __s[1];
                            {
                              const __s = __concat(v_s2, String(v_actual));
                              switch (__s[0]) {
                                case 0: {
                                  const v__do_e_15_5 = __s[1];
                                  return [0, v__do_e_15_5];
                                }
                                case 1: {
                                  const v_s3 = __s[1];
                                  return __concat(v_s3, ")");
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

const v_run = ((s) => { switch(s[0]) { case 0: { const v__do_e_20_3 = s[1]; return [0, v__do_e_20_3]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_3 = s[1]; return [0, v__do_e_21_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_3 = s[1]; return [0, v__do_e_22_3]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_3 = s[1]; return [0, v__do_e_23_3]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_3 = s[1]; return [0, v__do_e_24_3]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_3 = s[1]; return [0, v__do_e_25_3]; } case 1: { const v_s2 = s[1]; return __concat(v_s2, v_c); } } })(__concat(v_s1, ", ")); } } })(__concat(v_s0, v_b)); } } })(__concat(v_a, ", ")); } } })((v_check)((4 >>> 0), __lengthUtf8Bytes("🔥"), "lengthUtf8Bytes")); } } })((v_check)((2 >>> 0), __lengthUtf16CodeUnits("🔥"), "lengthUtf16CodeUnits")); } } })((v_check)((1 >>> 0), __lengthCodePoints("🔥"), "lengthCodePoints"));

function main(v__input){
    {
      const __s = v_run;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();