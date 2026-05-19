"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [3, [16]] : [4, a + b]; }

function v_runIO(v_io){
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
                v_io = null;
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

const v_ok = [4, (10|0)];

const v_bad = [3, [20]];

const main = (v__let_16)((v__df_mapRight_0)(v_ok));

function v__let_12(v_msg){
    {
      const __s = v_msg;
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
}

function v__lam_13(v_n){
    return v_n;
}

function v__let_14(v_mappedOk, v_mappedBad){
    return (v__let_12)(((s) => { switch(s[0]) { case 3: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 20: { return [4, "ok-Err"]; } } })(v___p0); } case 4: { const v_n = s[1]; return ((s) => { switch(s[0]) { case 3: { const v___p0 = s[1]; return ((s) => { switch(s[0]) { case 20: { return __concat("ok-Right ", String(v_n)); } } })(v___p0); } case 4: { const v__m = s[1]; return [4, "bad-Right"]; } } })(v_mappedBad); } } })(v_mappedOk));
}

function v__lam_15(v_n){
    return v_n;
}

function v__let_16(v_mappedOk){
    return (v__let_14)(v_mappedOk, (v__df_mapRight_1)(v_bad));
}

function v__df_mapRight_0(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return [4, (v__lam_15)(v_a)];
        }
      }
    }
}

function v__df_mapRight_1(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return [4, (v__lam_13)(v_a)];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();