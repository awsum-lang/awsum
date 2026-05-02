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
          return "Nothing";
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
                      return "Just True";
                    }
                    case 1: {
                      return "Just False";
                    }
                  }
                }
              }
              case 1759602215: {
                const v_u = __s[1];
                return ("Just " + (v_showUnit)(v_u));
              }
            }
          }
        }
      }
    }
}

const v_summary = (((((v_whatsInside)([1, [796142685, [0]]]) + "; ") + (v_whatsInside)([1, [1759602215, [0]]])) + "; ") + (v_whatsInside)([0]));

function main(v__input){
    return __print(v_summary);
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();