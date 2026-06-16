"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __succInt32 = x => x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];

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

  const v__apply__lift_18 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 19: {
          return v__x;
        }
        case 20: {
          const v__pk_20 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_20;
          continue;
        }
      }
    }
  };

  const v__cps__lift_18 = (v___input, v__k) => {
    while (true) {
      switch (v___input[0]) {
        case 5: {
          return v__apply__lift_18(v__k, v___input);
        }
        case 6: {
          const v___f0 = v___input[1];
          return v__apply__lift_18(v__k, [6, [882564211, v___f0]]);
        }
        case 7: {
          const v___f0 = v___input[1];
          const v___f1 = v___input[2];
          v__k = [20, v__k, v___f0];
          v___input = v___f1;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 21: {
          return v__x;
        }
        case 22: {
          const v__pk_22 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_22;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_0(
            v__k,
            (s => {
              switch (s[0]) {
                case 882564211: {
                  return [7, "OVERFLOW", [5, [0]]];
                }
                case 3768445577: {
                  return [7, "UNDERFLOW", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [22, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df__rowmono_1_andThenIO_8 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_1_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_1_andThenIO_8(
            v__k,
            v__cps__lift_18(
              (v__inl6_x_u1 =>
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [6, v__inl6_x_u1[1]];
                    }
                    case 4: {
                      return [5, v__inl6_x_u1[1]];
                    }
                  }
                })(v__inl6_x_u1))(__succInt32(v_io[1])),
              [19]
            )
          );
        }
        case 6: {
          const v_e = v_io[1];
          return v__apply__df__rowmono_1_andThenIO_8(
            v__k,
            [6, [3768445577, v_e]]
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

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_24;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_andThenIO_4(
            v__k,
            [7, String(v_io[1]), [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [24, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_andThenIO_4(
      v__cps__df__rowmono_1_andThenIO_8(
        (v__inl11_x_u1 =>
          (s => {
            switch (s[0]) {
              case 3: {
                return [6, v__inl11_x_u1[1]];
              }
              case 4: {
                return [5, v__inl11_x_u1[1]];
              }
            }
          })(v__inl11_x_u1))([4, 6 | 0]),
        [25]
      ),
      [23]
    ),
    [21]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
