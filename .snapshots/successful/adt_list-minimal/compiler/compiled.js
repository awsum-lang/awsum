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

  const v__apply__scc_show_showCons = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 17: {
          return v__x;
        }
        case 18: {
          const v__pk_18 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_18;
              continue;
            }
            case 4: {
              v__x = __concat(v__k[2], v__x[1]);
              v__k = v__pk_18;
              continue;
            }
          }
        }
      }
    }
  };

  const v__cps__scc_show_showCons = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 15: {
          const v_xs = v__args[1];
          switch (v_xs[0]) {
            case 13: {
              return v__apply__scc_show_showCons(v__k, [4, ""]);
            }
            case 14: {
              const v_h = v_xs[1];
              const v_t = v_xs[2];
              v__args = [16, v_h, v_t];
              continue;
            }
          }
        }
        case 16: {
          const v_h = v__args[1];
          const v_t = v__args[2];
          {
            const __s = __concat(v_h, ",");
            switch (__s[0]) {
              case 3: {
                const v__do_e_1 = __s[1];
                return v__apply__scc_show_showCons(v__k, [3, v__do_e_1]);
              }
              case 4: {
                const v_hc = __s[1];
                v__k = (v__args[0] = 18, v__args[1] = v__k, v__args[2] = v_hc, v__args);
                v__args = [15, v_t];
                continue;
              }
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
  })(
    v__cps__scc_show_showCons([15, [14, "a", [14, "b", [14, "c", [13]]]]], [17])
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
