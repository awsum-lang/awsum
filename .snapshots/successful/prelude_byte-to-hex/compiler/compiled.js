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

  const v__apply_bytesToHexStringNoPrefix = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
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
          v__k = [21, v__k, v_b];
          v_bytes = v_rest;
          continue;
        }
      }
    }
  };

  const v_res = v__cps_bytesToHexStringNoPrefix(
    [
      14,
      0 & 0xFF,
      [14, 15 & 0xFF, [14, 16 & 0xFF, [14, 171 & 0xFF, [14, 255 & 0xFF, [13]]]]]
    ],
    [20]
  );

  const v__apply__df_handleErrorIO_1 = (v__k, v__x) => {
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
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_5 = (v__k, v__x) => {
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
          v__k = [25, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl5_x = v_res;
  const main = v__cps__df_handleErrorIO_1(
    v__cps__df_andThenIO_5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl5_x[1]];
          }
          case 4: {
            return [5, v__inl5_x[1]];
          }
        }
      })(v__inl5_x),
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
