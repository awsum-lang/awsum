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

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v__inl7__do_e_2 = s[1];
        return [3, v__inl7__do_e_2];
      }
      case 4: {
        const v__inl8_s0 = s[1];
        {
          const __s = __concat(v__inl8_s0, "hello");
          switch (__s[0]) {
            case 3: {
              const v__inl9__do_e_1 = __s[1];
              return [3, v__inl9__do_e_1];
            }
            case 4: {
              const v__inl10_s1 = __s[1];
              {
                const __s = __concat(v__inl10_s1, "/");
                switch (__s[0]) {
                  case 3: {
                    const v__inl11__do_e_0 = __s[1];
                    return [3, v__inl11__do_e_0];
                  }
                  case 4: {
                    const v__inl12_s2 = __s[1];
                    return __concat(v__inl12_s2, "A");
                  }
                }
              }
            }
          }
        }
      }
    }
  })(__concat(String(42 | 0), "/"));

  const v__apply__df_handleErrorIO_1 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_1 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_1(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_1(
            v__k,
            [7, "STRING_TOO_LONG", [5, [0]]]
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

  const v__apply__df_andThenIO_5 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
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
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl15_x = v_res;
  const main = v__cps__df_handleErrorIO_1(
    v__cps__df_andThenIO_5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl15_x[1]];
          }
          case 4: {
            return [5, v__inl15_x[1]];
          }
        }
      })(v__inl15_x),
      [27]
    ),
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
