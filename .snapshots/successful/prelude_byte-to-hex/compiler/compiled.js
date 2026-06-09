"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const v_runIO = (v_io) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__lam_12 = (v_b, v_restHex) => {
    return __concat(v_b.toString(16).padStart(2, "0"), v_restHex);
  };

  const v__df_bindEither_0 = (v_x, v__df_bindEither_0_cap1_0) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lam_12(v__df_bindEither_0_cap1_0, v_a);
        }
      }
    }
  };

  const v__apply_bytesToHexStringNoPrefix = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 15: {
            return v__x;
          }
          case 16: {
            const v__pk_16 = __s[1];
            const v_b = __s[2];
            const __t0 = v__pk_16;
            const __t1 = v__df_bindEither_0(v__x, v_b);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps_bytesToHexStringNoPrefix = (v_bytes, v__k) => {
    while (true) {
      {
        const __s = v_bytes;
        switch (__s[0]) {
          case 13: {
            return v__apply_bytesToHexStringNoPrefix(v__k, [4, ""]);
          }
          case 14: {
            const v_b = __s[1];
            const v_rest = __s[2];
            const __t0 = v_rest;
            const __t1 = (v_bytes[0] = 16, v_bytes[1] = v__k, v_bytes[2] = v_b, v_bytes);
            v_bytes = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v_bytesToHexStringNoPrefix = (v_bytes) => {
    return v__cps_bytesToHexStringNoPrefix(v_bytes, [15]);
  };

  const v__let_13 = (v_bytes) => {
    {
      const __s = v_bytesToHexStringNoPrefix(v_bytes);
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return [7, "TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_hex = __s[1];
          return [7, v_hex, [5, [0]]];
        }
      }
    }
  };

  const main = v__let_13(
    [
      14,
      0 & 0xFF,
      [14, 15 & 0xFF, [14, 16 & 0xFF, [14, 171 & 0xFF, [14, 255 & 0xFF, [13]]]]]
    ]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
