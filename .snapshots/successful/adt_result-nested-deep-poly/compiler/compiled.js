"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_unwrap(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 0: {
                const v___p0_p0 = __s[1];
                {
                  const __s = v___p0_p0;
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
                const v___p0_p0 = __s[1];
                {
                  const __s = v___p0_p0;
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
        case 1: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 0: {
                const v___p0_p0 = __s[1];
                {
                  const __s = v___p0_p0;
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
                const v___p0_p0 = __s[1];
                {
                  const __s = v___p0_p0;
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
      }
    }
}

function main(v__input){
    return __print((((((((((((((((v_unwrap)([0, [0, [0, "1"]]]) + ",") + (v_unwrap)([0, [0, [1, "2"]]])) + ",") + (v_unwrap)([0, [1, [0, "3"]]])) + ",") + (v_unwrap)([0, [1, [1, "4"]]])) + ",") + (v_unwrap)([1, [0, [0, "5"]]])) + ",") + (v_unwrap)([1, [0, [1, "6"]]])) + ",") + (v_unwrap)([1, [1, [0, "7"]]])) + ",") + (v_unwrap)([1, [1, [1, "8"]]])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();