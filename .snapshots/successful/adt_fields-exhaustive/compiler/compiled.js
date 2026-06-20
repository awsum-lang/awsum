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

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_27;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl2_p = [15, [25], [24]];
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 24: {
                    return "A?";
                  }
                  case 25: {
                    return "B?";
                  }
                }
              })(v__inl2_p[1]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [27, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl5_p = [15, [24], [25]];
  const main = v__cps__df_andThenIO_0(
    [
      7,
      (s => {
        switch (s[0]) {
          case 15: {
            const v__inl4___p1 = s[2];
            {
              const __s = v__inl5_p[1];
              switch (__s[0]) {
                case 24: {
                  switch (v__inl4___p1[0]) {
                    case 24: {
                      return "AA";
                    }
                    case 25: {
                      return "AB";
                    }
                  }
                }
                case 25: {
                  switch (v__inl4___p1[0]) {
                    case 24: {
                      return "BA";
                    }
                    case 25: {
                      return "BB";
                    }
                  }
                }
              }
            }
          }
        }
      })(v__inl5_p),
      [5, [0]]
    ],
    [26]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
