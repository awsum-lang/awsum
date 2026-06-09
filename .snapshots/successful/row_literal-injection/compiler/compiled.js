"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __eqInt32 = (a, b) => {
    return a === b ? [1] : [2];
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

  const v_gU = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [3538687084, 11 >>> 0];
        }
        case 2: {
          return [3538687084, 13 >>> 0];
        }
      }
    }
  };

  const v_gBare = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [2711245919, 7 | 0];
        }
        case 2: {
          return [2711245919, 9 | 0];
        }
      }
    }
  };

  const v_gAsc = (v_n) => {
    {
      const __s = __eqInt32(v_n, 0 | 0);
      switch (__s[0]) {
        case 1: {
          return [2711245919, 7 | 0];
        }
        case 2: {
          return [2711245919, 9 | 0];
        }
      }
    }
  };

  const v_extractU = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3538687084: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
  };

  const v_extract = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 2711245919: {
          const v_n = __s[1];
          return v_n;
        }
      }
    }
  };

  const v__lam_17 = (v__u) => {
    return [7, String(v_extract(v_gAsc(1 | 0))), [5, [0]]];
  };

  const v__lam_16 = (v__u) => {
    return [7, String(v_extract(v_gBare(0 | 0))), [5, [0]]];
  };

  const v__lam_15 = (v__u) => {
    return [7, String(v_extract(v_gBare(1 | 0))), [5, [0]]];
  };

  const v__lam_14 = (v__u) => {
    return [7, String(v_extractU(v_gU(0 | 0))), [5, [0]]];
  };

  const v__lam_13 = (v__u) => {
    return [7, String(v_extractU(v_gU(1 | 0))), [5, [0]]];
  };

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 12: {
            return v__x;
          }
          case 13: {
            const v__pk_13 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_13;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_8(v__k, v__lam_15(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 13, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_8 = (v_io) => {
    return v__cps__df_andThenIO_8(v_io, [12]);
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 10: {
            return v__x;
          }
          case 11: {
            const v__pk_11 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_11;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_4(v__k, v__lam_14(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 11, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_4 = (v_io) => {
    return v__cps__df_andThenIO_4(v_io, [10]);
  };

  const v__apply__df_andThenIO_16 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 16: {
            return v__x;
          }
          case 17: {
            const v__pk_17 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_17;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_16 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_16(v__k, v__lam_17(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 17, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_16 = (v_io) => {
    return v__cps__df_andThenIO_16(v_io, [16]);
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 14: {
            return v__x;
          }
          case 15: {
            const v__pk_15 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_15;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_12(v__k, v__lam_16(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 15, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_12 = (v_io) => {
    return v__cps__df_andThenIO_12(v_io, [14]);
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 8: {
            return v__x;
          }
          case 9: {
            const v__pk_9 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_9;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_0(v__k, v__lam_13(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 9, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_0 = (v_io) => {
    return v__cps__df_andThenIO_0(v_io, [8]);
  };

  const main = v__df_andThenIO_0(
    v__df_andThenIO_4(
      v__df_andThenIO_8(
        v__df_andThenIO_12(
          v__df_andThenIO_16([7, String(v_extract(v_gAsc(0 | 0))), [5, [0]]])
        )
      )
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
