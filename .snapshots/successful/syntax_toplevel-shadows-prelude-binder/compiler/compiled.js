"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = (x) => {
    return x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];
  };

  const __succInt32 = (x) => {
    return x === 2147483647 ? [3, [18]] : [4, x + 1 | 0];
  };

  const v_x = (v_n) => {
    return __predInt32(v_n);
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

  const v_pureIO = (v_x_u0) => {
    return [5, v_x_u0];
  };

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v_eitherToIO = (v_x_u1) => {
    {
      const __s = v_x_u1;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return v_failIO(v_e);
        }
        case 4: {
          const v_a_u1 = __s[1];
          return v_pureIO(v_a_u1);
        }
      }
    }
  };

  const v_a = (v_n) => {
    return __succInt32(v_n);
  };

  const v__lam_15 = (v_v) => {
    return v_eitherToIO(v_a(v_v));
  };

  const v__lam_14 = (v_w) => {
    return [7, String(v_w), [5, [0]]];
  };

  const v__lam_13 = (v__e) => {
    return [7, "err", [5, [0]]];
  };

  const v__apply__lift_19 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 8: {
            return v__x;
          }
          case 9: {
            const v__pk_9 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_9;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_19 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_19(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_19(v__k, [6, [882564211, v___f0]]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 9, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__lift_19 = (v___input) => {
    return v__cps__lift_19(v___input, [8]);
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a_u0 = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [5, v_a_u0]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, v__lam_13(v_e));
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

  const v__df_handleErrorIO_0 = (v_io) => {
    return v__cps__df_handleErrorIO_0(v_io, [10]);
  };

  const v__apply__df__rowmono_1_andThenIO_8 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_1_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a_u3 = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(
              v__k,
              v__lift_19(v__lam_15(v_a_u3))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_1_andThenIO_8(
              v__k,
              [6, [3768445577, v_e]]
            );
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

  const v__df__rowmono_1_andThenIO_8 = (v_io) => {
    return v__cps__df__rowmono_1_andThenIO_8(v_io, [14]);
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a_u2 = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, v__lam_14(v_a_u2));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_andThenIO_4(v__k, [6, v_e]);
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

  const v__df__rowmono_0_andThenIO_4 = (v_io) => {
    return v__cps__df__rowmono_0_andThenIO_4(v_io, [12]);
  };

  const main = v__df_handleErrorIO_0(
    v__df__rowmono_0_andThenIO_4(
      v__df__rowmono_1_andThenIO_8(v_eitherToIO(v_x(7 | 0)))
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
