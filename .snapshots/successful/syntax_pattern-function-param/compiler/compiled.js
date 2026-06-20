"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_triple = [16, 10 | 0, 20 | 0, 30 | 0];

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

  const v_pair = [15, 100 | 0, 200 | 0];

  const v__inl14__arg_0 = v_triple;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__inl15__do_e_3 = s[1];
        return [3, v__inl15__do_e_3];
      }
      case 4: {
        const v__inl16_s0 = s[1];
        const v__inl17_t = v_pair;
        return __concat(
          v__inl16_s0,
          String(
            (s => {
              switch (s[0]) {
                case 3: {
                  return 0 | 0;
                }
                case 4: {
                  const v__inl19_s = s[1];
                  return v__inl19_s;
                }
              }
            })(__addInt32(v__inl17_t[1], v__inl17_t[2]))
          )
        );
      }
    }
  })(
    __concat(
      String(
        (s => {
          switch (s[0]) {
            case 3: {
              return 0 | 0;
            }
            case 4: {
              const v__inl11_ab = s[1];
              {
                const __s = __addInt32(v__inl11_ab, v__inl14__arg_0[3]);
                switch (__s[0]) {
                  case 3: {
                    return 0 | 0;
                  }
                  case 4: {
                    const v__inl13_abc = __s[1];
                    return v__inl13_abc;
                  }
                }
              }
            }
          }
        })(__addInt32(v__inl14__arg_0[1], v__inl14__arg_0[2]))
      ),
      " / "
    )
  );

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_21;
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
          v__k = [21, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl22_x = v_res;
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl22_x[1]];
          }
          case 4: {
            return [5, v__inl22_x[1]];
          }
        }
      })(v__inl22_x),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
