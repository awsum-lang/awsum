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

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_30;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl11_e = [4, "ok"];
          return v__apply__df_andThenIO_8(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 3: {
                    return String(v__inl11_e[1]);
                  }
                  case 4: {
                    return v__inl11_e[1];
                  }
                }
              })(v__inl11_e),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [30, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl14_xs = [14, 3 | 0, [13]];
          return v__apply__df_andThenIO_4(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 13: {
                    return "empty";
                  }
                  case 14: {
                    return String(v__inl14_xs[1]);
                  }
                }
              })(v__inl14_xs),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_0(
            v__k,
            [
              7,
              (s => {
                switch (s[0]) {
                  case 11: {
                    return "none";
                  }
                  case 12: {
                    const v__inl17___p0 = s[1];
                    return String(v__inl17___p0[1]);
                  }
                }
              })([12, [24, 6 | 0]]),
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

  const v__inl19_m = [12, 5 | 0];
  const main = v__cps__df_andThenIO_0(
    v__cps__df_andThenIO_4(
      v__cps__df_andThenIO_8(
        [
          7,
          (s => {
            switch (s[0]) {
              case 11: {
                return "none";
              }
              case 12: {
                return String(v__inl19_m[1]);
              }
            }
          })(v__inl19_m),
          [5, [0]]
        ],
        [29]
      ),
      [27]
    ),
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
