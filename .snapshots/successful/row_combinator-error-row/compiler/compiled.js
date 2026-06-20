"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v_c2 = [3, [332136403, [24]]];

  const v_c1 = [3, [332136403, [24]]];

  const v__apply__df_andThenIO_2 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          const v__pk_26 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_26;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_2 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl21_x = v_c2;
          return v__apply__df_andThenIO_2(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    {
                      const __s = v__inl21_x[1];
                      switch (__s[0]) {
                        case 332136403: {
                          return "A";
                        }
                      }
                    }
                  }
                  case 4: {
                    return String(v__inl21_x[1]);
                  }
                }
              })(v__inl21_x),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [26, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl30_x = v_c1;
  const main = v__cps__df_andThenIO_2(
    [
      7,
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl30_x[1];
              switch (__s[0]) {
                case 332136403: {
                  return "A";
                }
              }
            }
          }
          case 4: {
            return String(v__inl30_x[1]);
          }
        }
      })(v__inl30_x),
      [5, [0]]
    ],
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
