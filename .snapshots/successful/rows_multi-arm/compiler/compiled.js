"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showUnit(v__wild0){
    return "Unit";
}

function v_whatsInside(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          return [1, "Nothing"];
        }
        case 1: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 796142685: {
                const v_b = __s[1];
                {
                  const __s = v_b;
                  switch (__s[0]) {
                    case 0: {
                      return [1, "Just True"];
                    }
                    case 1: {
                      return [1, "Just False"];
                    }
                  }
                }
              }
              case 1759602215: {
                const v_u = __s[1];
                return [1, ("Just " + (v_showUnit)(v_u))];
              }
            }
          }
        }
      }
    }
}

const v_summary = ((s) => { switch(s[0]) { case 0: { const v__do_e_15_3 = s[1]; return [0, v__do_e_15_3]; } case 1: { const v_a = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_16_3 = s[1]; return [0, v__do_e_16_3]; } case 1: { const v_b = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_17_3 = s[1]; return [0, v__do_e_17_3]; } case 1: { const v_c = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_18_3 = s[1]; return [0, v__do_e_18_3]; } case 1: { const v_s0 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_19_3 = s[1]; return [0, v__do_e_19_3]; } case 1: { const v_s1 = s[1]; return ((s) => { switch(s[0]) { case 0: { const v__do_e_20_3 = s[1]; return [0, v__do_e_20_3]; } case 1: { const v_s2 = s[1]; return [1, (v_s2 + v_c)]; } } })([1, (v_s1 + "; ")]); } } })([1, (v_s0 + v_b)]); } } })([1, (v_a + "; ")]); } } })((v_whatsInside)([0])); } } })((v_whatsInside)([1, [1759602215, [0]]])); } } })((v_whatsInside)([1, [796142685, [0]]]));

function main(v__input){
    return (v__let_1)(v_summary);
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