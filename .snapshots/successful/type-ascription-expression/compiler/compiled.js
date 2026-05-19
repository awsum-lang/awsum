"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __predInt32(x){ return x === -2147483648 ? [3, [14]] : [4, ((x - 1)|0)]; }
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

function v_identity(v_x){
    return v_x;
}

const v_direct = String((42|0));

const v_throughHof = String((v_identity)((10|0)));

const v_ascribedCall = ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return "FAIL"; } case 4: { const v_n = s[1]; return String(v_n); } } })(__predInt32((5|0)));

const v_joined = ((s) => { switch(s[0]) { case 3: { const v__do_e_34_3 = s[1]; return [3, v__do_e_34_3]; } case 4: { const v_ab = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_35_3 = s[1]; return [3, v__do_e_35_3]; } case 4: { const v_abc = s[1]; return ((s) => { switch(s[0]) { case 3: { const v__do_e_36_3 = s[1]; return [3, v__do_e_36_3]; } case 4: { const v_abcd = s[1]; return __concat(v_abcd, v_ascribedCall); } } })(__concat(v_abc, " ")); } } })(__concat(v_ab, v_throughHof)); } } })(__concat(v_direct, " "));

const main = ((s) => { switch(s[0]) { case 3: { const v___w0 = s[1]; return [7, "OVERFLOW", [5, [0]]]; } case 4: { const v_s = s[1]; return [7, v_s, [5, [0]]]; } } })(v_joined);

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();