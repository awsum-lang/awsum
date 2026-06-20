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

  const v__apply__scc_show_showCons = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = v__k[1];
          switch (v__x[0]) {
            case 3: {
              v__k = v__pk_29;
              continue;
            }
            case 4: {
              const v_rest = v__x[1];
              {
                const __s = __concat(v__k[2], ",");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_0 = __s[1];
                    v__k = v__pk_29;
                    v__x = [3, v__do_e_0];
                    continue;
                  }
                  case 4: {
                    const v_comma = __s[1];
                    v__k = v__pk_29;
                    v__x = __concat(v_comma, v_rest);
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

  const v__cps__scc_show_showCons = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 20: {
          const v_xs = v__args[1];
          switch (v_xs[0]) {
            case 13: {
              return v__apply__scc_show_showCons(v__k, [4, ""]);
            }
            case 14: {
              const v_h = v_xs[1];
              const v_t = v_xs[2];
              v__args = [21, v_h, v_t];
              continue;
            }
          }
        }
        case 21: {
          const v_h = v__args[1];
          const v_t = v__args[2];
          switch (v_h[0]) {
            case 3: {
              return v__apply__scc_show_showCons(v__k, v_h);
            }
            case 4: {
              v__k = (v__args[0] = 29, v__args[1] = v__k, v__args[2] = v_h[1], v__args);
              v__args = [20, v_t];
              continue;
            }
          }
        }
      }
    }
  };

  const v__apply__df_map_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 22: {
          return v__x;
        }
        case 23: {
          const v__pk_23 = v__k[1];
          const v_head = v__k[2];
          v__x = (v__k[0] = 14, v__k[1] = __concat(
            v_head,
            "!"
          ), v__k[2] = v__x, v__k);
          v__k = v__pk_23;
          continue;
        }
      }
    }
  };

  const v__cps__df_map_0 = (v_list, v__k) => {
    while (true) {
      switch (v_list[0]) {
        case 13: {
          return v__apply__df_map_0(v__k, v_list);
        }
        case 14: {
          const v_head = v_list[1];
          const v_tail = v_list[2];
          v__k = [23, v__k, v_head];
          v_list = v_tail;
          continue;
        }
      }
    }
  };

  const v_res = v__cps__scc_show_showCons(
    [20, v__cps__df_map_0([14, "a", [14, "b", [14, "c", [13]]]], [22])],
    [28]
  );

  const v__apply__df_handleErrorIO_1 = (v__k, v__x) => {
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
          v__k = [25, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_5 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 26: {
          return v__x;
        }
        case 27: {
          const v__pk_27 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_27;
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
          v__k = [27, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl3_x = v_res;
  const main = v__cps__df_handleErrorIO_1(
    v__cps__df_andThenIO_5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl3_x[1]];
          }
          case 4: {
            return [5, v__inl3_x[1]];
          }
        }
      })(v__inl3_x),
      [26]
    ),
    [24]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
