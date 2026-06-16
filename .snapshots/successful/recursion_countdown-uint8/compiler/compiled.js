"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predUInt8 = x => x === 0 ? [3, [17]] : [4, x - 1 & 0xFF];

  const __eqUInt8 = (a, b) => a === b ? [1] : [2];

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

  const v__apply_countDown = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_21;
              continue;
            }
            case 4: {
              const v_s = v__x[1];
              {
                const __s = __concat(String(v__k[2]), ",");
                switch (__s[0]) {
                  case 3: {
                    const v_e = __s[1];
                    v__k = v__pk_21;
                    v__x = [3, [589989748, v_e]];
                    continue;
                  }
                  case 4: {
                    const v_s0 = __s[1];
                    v__k = v__pk_21;
                    v__x = (v__inl3___input =>
                      (s => {
                        switch (s[0]) {
                          case 3: {
                            return [3, [589989748, v__inl3___input[1]]];
                          }
                          case 4: {
                            return v__inl3___input;
                          }
                        }
                      })(v__inl3___input))(__concat(v_s0, v_s));
                    continue;
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const v__cps_countDown = (v_n, v__k) => {
    while (true) {
      {
        const __s = __eqUInt8(v_n, 0 & 0xFF);
        switch (__s[0]) {
          case 1: {
            return v__apply_countDown(v__k, [4, String(v_n)]);
          }
          case 2: {
            {
              const __s = __predUInt8(v_n);
              switch (__s[0]) {
                case 3: {
                  const v_e = __s[1];
                  return v__apply_countDown(v__k, [3, [3768445577, v_e]]);
                }
                case 4: {
                  const v_m = __s[1];
                  v__k = [21, v__k, v_n];
                  v_n = v_m;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_res = (v__inl8_r =>
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v__inl8_r[1];
            switch (__s[0]) {
              case 589989748: {
                return [4, "STRING_TOO_LONG"];
              }
              case 3768445577: {
                return __concat("left: ", "UnderflowError");
              }
            }
          }
        }
        case 4: {
          return __concat("right: ", v__inl8_r[1]);
        }
      }
    })(v__inl8_r))(v__cps_countDown(255 & 0xFF, [20]));

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_23;
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
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 24: {
          return v__x;
        }
        case 25: {
          const v__pk_25 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_25;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [25, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (v__inl11_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return [6, v__inl11_x[1]];
            }
            case 4: {
              return [5, v__inl11_x[1]];
            }
          }
        })(v__inl11_x))(v_res),
      [24]
    ),
    [22]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
