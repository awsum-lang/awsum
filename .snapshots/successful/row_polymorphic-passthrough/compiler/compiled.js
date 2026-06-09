"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_v = [1615808600, "poly"];

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

  const v_myId = (v_x) => {
    return v_x;
  };

  const v_w = v_myId(v_v);

  const v_myFirst = (v_x, v__y) => {
    return v_x;
  };

  const v_z = v_myFirst(v_v, [1]);

  const v_d = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 1615808600: {
          const v_s = __s[1];
          return v_s;
        }
      }
    }
  };

  const v__lam_13 = (v__u) => {
    return [7, v_d(v_z), [5, [0]]];
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

  const main = v__df_andThenIO_0([7, v_d(v_w), [5, [0]]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
