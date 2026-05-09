"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }
function __getArgs(){ return __entryArgEither(process.argv[2] ?? ""); }

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
        case 3: {
          const v_cont = __s[1];
          const __t0 = (v__apply1)(v_cont, __getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  }
}

function v_showToken(v_token){
    {
      const __s = v_token;
      switch (__s[0]) {
        case 0: {
          const v_w = __s[1];
          return __concat("word:", v_w);
        }
        case 1: {
          const v_n = __s[1];
          return __concat("num:", v_n);
        }
        case 2: {
          return [1, ","];
        }
        case 3: {
          return [1, "<eof>"];
        }
      }
    }
}

const main = (v__let_7)(((s) => { switch(s[0]) { case 0: { const v__do_e_20_9 = s[1]; return [0, v__do_e_20_9]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_21_9 = s[1]; return [0, v__do_e_21_9]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_22_9 = s[1]; return [0, v__do_e_22_9]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_23_9 = s[1]; return [0, v__do_e_23_9]; } case 1: { const v_d = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_24_9 = s[1]; return [0, v__do_e_24_9]; } case 1: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_25_9 = s[1]; return [0, v__do_e_25_9]; } case 1: { const v_abc = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_26_9 = s[1]; return [0, v__do_e_26_9]; } case 1: { const v_abcs = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_27_9 = s[1]; return [0, v__do_e_27_9]; } case 1: { const v_abcsc = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_abcscd = s[1]; return __concat(v_abcscd, v_d); } } })(__concat(v_abcsc, " ")); } } })(__concat(v_abcs, v_c)); } } })(__concat(v_abc, " ")); } } })(__concat(v_ab, v_b)); } } })(__concat(v_a, " ")); } } })((v_showToken)([3])); } } })((v_showToken)([1, "42"])); } } })((v_showToken)([2])); } } })((v_showToken)([0, "hello"])));

function v__let_7(v_res){
    {
      const __s = v_res;
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

function v__apply1(v__cl, v__arg0){
    {
      const __s = v__cl;
      switch (__s[0]) {
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();