"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

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

  const v__apply__df_bindIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 10: {
          return v__x;
        }
        case 11: {
          const v__pk_11 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_11;
          continue;
        }
      }
    }
  };

  const v__cps__df_bindIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_bindIO_4(v__k, [7, "c", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [11, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_bindIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 8: {
          return v__x;
        }
        case 9: {
          const v__pk_9 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_9;
          continue;
        }
      }
    }
  };

  const v__cps__df_bindIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_bindIO_0(
            v__k,
            v__cps__df_bindIO_4([7, "b", [5, [0]]], [10])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [9, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_bindIO_0([7, "a", [5, [0]]], [8]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
