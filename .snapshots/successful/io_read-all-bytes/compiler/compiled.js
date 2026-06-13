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
        case 19: {
          return v__x;
        }
        case 20: {
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
          v__k = [20, v__k, v_b];
          v_bytes = v_rest;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_1 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_1 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_1(
            v__k,
            (s => {
              switch (s[0]) {
                case 3: {
                  return [7, "TOO_LONG", [5, [0]]];
                }
                case 4: {
                  const v__inl3_hex = s[1];
                  return [7, v__inl3_hex, [5, [0]]];
                }
              }
            })(v__cps_bytesToHexStringNoPrefix(v_io[1], [19]))
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [22, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 10: {
          const v_cont = v_io[1];
          return v__apply__df_andThenIO_1(v__k, [10, [15, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_2_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          v__k = v__k[1];
          v__x = v__cps__df_andThenIO_1(v__x, [21]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_2_4 = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 17: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 15: {
              v__args = (v__args[0] = 18, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 16: {
              return v__apply__scc__apply1__df__lam_2_4(v__k, [5, v__arg0]);
            }
          }
        }
        case 18: {
          v__args = (v__args[0] = 17, v__args);
          v__k = [24, v__k];
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
          const v__inl4_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 10: {
          const __t0 = (v__inl5__arg0 =>
            v__cps__scc__apply1__df__lam_2_4(
              [17, v_io[1], v__inl5__arg0],
              [23]
            ))(__stdinReadAllBytes());
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_1([10, [16]], [21]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
