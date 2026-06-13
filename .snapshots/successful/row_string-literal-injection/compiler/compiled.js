"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_sv = [1615808600, "S"];

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

  const v_iv = [2711245919, 9 | 0];

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 12: {
          return v__x;
        }
        case 13: {
          const v__pk_13 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_13;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_8(
            v__k,
            [
              7,
              (v__inl18_x =>
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return v__inl18_x[1];
                    }
                    case 2711245919: {
                      return String(v__inl18_x[1]);
                    }
                  }
                })(v__inl18_x))([1615808600, "T"]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [13, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 10: {
          return v__x;
        }
        case 11: {
          const v__pk_11 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_11;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(
            v__k,
            [
              7,
              (v__inl21_x =>
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return v__inl21_x[1];
                    }
                    case 2711245919: {
                      return String(v__inl21_x[1]);
                    }
                  }
                })(v__inl21_x))([2711245919, 1 | 0]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [11, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 14: {
          return v__x;
        }
        case 15: {
          const v__pk_15 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_15;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_12(
            v__k,
            [
              7,
              (v__inl24_x =>
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return v__inl24_x[1];
                    }
                    case 2711245919: {
                      return String(v__inl24_x[1]);
                    }
                  }
                })(v__inl24_x))(v_iv),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [15, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 8: {
          return v__x;
        }
        case 9: {
          const v__pk_9 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_9;
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
              (v__inl27_lv =>
                (s => {
                  switch (s[0]) {
                    case 1615808600: {
                      return v__inl27_lv[1];
                    }
                    case 2711245919: {
                      return String(v__inl27_lv[1]);
                    }
                  }
                })(v__inl27_lv))([1615808600, "L"]),
              [5, [0]]
            ]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [9, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_0(
    v__cps__df_andThenIO_4(
      v__cps__df_andThenIO_8(
        v__cps__df_andThenIO_12(
          [
            7,
            (v__inl32_x =>
              (s => {
                switch (s[0]) {
                  case 1615808600: {
                    return v__inl32_x[1];
                  }
                  case 2711245919: {
                    return String(v__inl32_x[1]);
                  }
                }
              })(v__inl32_x))(v_sv),
            [5, [0]]
          ],
          [14]
        ),
        [12]
      ),
      [10]
    ),
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
