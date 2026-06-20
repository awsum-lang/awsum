"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

  const v__apply_bytesToHexStringNoPrefix = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          v__x = (s => {
            switch (s[0]) {
              case 3: {
                return v__x;
              }
              case 4: {
                return __concat(v__k[2].toString(16).padStart(2, "0"), v__x[1]);
              }
            }
          })(v__x);
          v__k = v__k[1];
          continue;
        }
      }
    }
  };

  const v__cps_bytesToHexStringNoPrefix = (v_bytes, v__k) => {
    while (true) {
      switch (v_bytes[0]) {
        case 13: {
          return v__apply_bytesToHexStringNoPrefix(v__k, [4, ""]);
        }
        case 14: {
          const v_b = v_bytes[1];
          const v_rest = v_bytes[2];
          v__k = [29, v__k, v_b];
          v_bytes = v_rest;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_1 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_31;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_1 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_1(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_1(v__k, [7, "TOO_LONG", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [31, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v__apply__df_handleErrorIO_1(v__k, [10, [20, v_cont]]);
        }
      }
    }
  };

  const v__apply__df_andThenIO_9 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 34: {
          return v__x;
        }
        case 35: {
          const v__pk_35 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_35;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_9 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl5_x = v__cps_bytesToHexStringNoPrefix(v_io[1], [28]);
          return v__apply__df_andThenIO_9(
            v__k,
            (s => {
              switch (s[0]) {
                case 3: {
                  return [6, v__inl5_x[1]];
                }
                case 4: {
                  return [5, v__inl5_x[1]];
                }
              }
            })(v__inl5_x)
          );
        }
        case 6: {
          return v__apply__df_andThenIO_9(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [35, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v__apply__df_andThenIO_9(v__k, [10, [21, v_cont]]);
        }
      }
    }
  };

  const v__apply__df_andThenIO_5 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 32: {
          return v__x;
        }
        case 33: {
          const v__pk_33 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_33;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_5 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_5(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_5(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [33, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v__apply__df_andThenIO_5(v__k, [10, [22, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_11_4__df__lam_2_12__df__lam_2_8 = (
    v__k,
    v__x
  ) => {
    while (true) {
      switch (v__k[0]) {
        case 36: {
          return v__x;
        }
        case 37: {
          v__k = v__k[1];
          v__x = v__cps__df_handleErrorIO_1(v__x, [30]);
          continue;
        }
        case 38: {
          v__k = v__k[1];
          v__x = v__cps__df_andThenIO_9(v__x, [34]);
          continue;
        }
        case 39: {
          v__k = v__k[1];
          v__x = v__cps__df_andThenIO_5(v__x, [32]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_11_4__df__lam_2_12__df__lam_2_8 = (
    v__args,
    v__k
  ) => {
    while (true) {
      switch (v__args[0]) {
        case 24: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 20: {
              v__args = (v__args[0] = 25, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 21: {
              v__args = (v__args[0] = 26, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 22: {
              v__args = (v__args[0] = 27, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 23: {
              return v__apply__scc__apply1__df__lam_11_4__df__lam_2_12__df__lam_2_8(
                v__k,
                [5, v__arg0]
              );
            }
          }
        }
        case 25: {
          v__args = (v__args[0] = 24, v__args);
          v__k = [37, v__k];
          continue;
        }
        case 26: {
          v__args = (v__args[0] = 24, v__args);
          v__k = [38, v__k];
          continue;
        }
        case 27: {
          v__args = (v__args[0] = 24, v__args);
          v__k = [39, v__k];
          continue;
        }
      }
    }
  };

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v__inl8_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 10: {
          const __t0 = (() => {
            const v__inl9__arg0 = __stdinReadAllBytes();
            return v__cps__scc__apply1__df__lam_11_4__df__lam_2_12__df__lam_2_8(
              [24, v_io[1], v__inl9__arg0],
              [36]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_1(
    v__cps__df_andThenIO_5(v__cps__df_andThenIO_9([10, [23]], [34]), [32]),
    [30]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
