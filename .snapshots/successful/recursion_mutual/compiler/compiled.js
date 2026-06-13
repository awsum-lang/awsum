"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v__apply__scc_handleA_handleB = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_31;
              continue;
            }
            case 4: {
              v__k = v__pk_31;
              v__x = __concat("A", v__x[1]);
              continue;
            }
          }
        }
        case 32: {
          const v__pk_32 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_32;
              continue;
            }
            case 4: {
              v__k = v__pk_32;
              v__x = __concat("B", v__x[1]);
              continue;
            }
          }
        }
        case 33: {
          const v__pk_33 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_33;
              continue;
            }
            case 4: {
              v__k = v__pk_33;
              v__x = __concat("C", v__x[1]);
              continue;
            }
          }
        }
      }
    }
  };

  const v__cps__scc_handleA_handleB = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 28: {
          const v_step = v__args[1];
          switch (v_step[0]) {
            case 24: {
              v__args = (v__args[0] = 29, v__args[1] = [25], v__args);
              v__k = [31, v__k];
              continue;
            }
            case 25: {
              v__args = (v__args[0] = 29, v__args);
              continue;
            }
            case 26: {
              v__args = (v__args[0] = 29, v__args);
              continue;
            }
            case 27: {
              return v__apply__scc_handleA_handleB(v__k, [4, ""]);
            }
          }
        }
        case 29: {
          const v_step = v__args[1];
          switch (v_step[0]) {
            case 24: {
              v__args = (v__args[0] = 28, v__args);
              continue;
            }
            case 25: {
              v__args = (v__args[0] = 28, v__args[1] = [26], v__args);
              v__k = [32, v__k];
              continue;
            }
            case 26: {
              v__args = (v__args[0] = 28, v__args[1] = [27], v__args);
              v__k = [33, v__k];
              continue;
            }
            case 27: {
              return v__apply__scc_handleA_handleB(v__k, [4, ""]);
            }
          }
        }
      }
    }
  };

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v__inl2_s = s[1];
        return [7, v__inl2_s, [5, [0]]];
      }
    }
  })(v__cps__scc_handleA_handleB([28, [24]], [30]));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
