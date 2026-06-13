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

  const v_inc42 = 42 | 0;

  const v_g = [4, 1 | 0];

  const main = (v__inl5_r =>
    (() => {
      let v__inl9_scrut;
      $join8: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              {
                const __s = v__inl5_r[1];
                switch (__s[0]) {
                  case 2252990199: {
                    return [4, "ErrA"];
                  }
                  case 2269767818: {
                    return [4, "ErrB"];
                  }
                }
              }
            }
            case 4: {
              return __concat("Ok ", String(v__inl5_r[1]));
            }
          }
        })(v__inl5_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_d = __s[1];
            v__inl9_scrut = (s => {
              switch (s[0]) {
                case 3: {
                  const v__do_e_2 = s[1];
                  return [3, v__do_e_2];
                }
                case 4: {
                  const v_s0 = s[1];
                  return __concat(v_s0, v_d);
                }
              }
            })(__concat(String(v_inc42), " / "));
            break $join8;
          }
        }
      }
      switch (v__inl9_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl9_scrut[1], [5, [0]]];
        }
      }
    })())(v_g);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
