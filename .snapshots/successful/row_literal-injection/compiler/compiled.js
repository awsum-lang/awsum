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

  const v__apply__df_andThenIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 12: {
          return v__x;
        }
        case 13: {
          const v__pk_13 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_13;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl6_x = [2711245919, 9 | 0];
          return v__apply__df_andThenIO_8(
            v__k,
            [7, String(v__inl6_x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [13, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl7_x = [3538687084, 11 >>> 0];
          return v__apply__df_andThenIO_4(
            v__k,
            [7, String(v__inl7_x[1]), [5, [0]]]
          );
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

  const v__apply__df_andThenIO_16 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 16: {
          return v__x;
        }
        case 17: {
          const v__pk_17 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_17;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_16 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl8_x = [2711245919, 9 | 0];
          return v__apply__df_andThenIO_16(
            v__k,
            [7, String(v__inl8_x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [17, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_12 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 14: {
          return v__x;
        }
        case 15: {
          const v__pk_15 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_15;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_12 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl9_x = [2711245919, 7 | 0];
          return v__apply__df_andThenIO_12(
            v__k,
            [7, String(v__inl9_x[1]), [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [15, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_0 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl10_x = [3538687084, 13 >>> 0];
          return v__apply__df_andThenIO_0(
            v__k,
            [7, String(v__inl10_x[1]), [5, [0]]]
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

  const v__inl11_x = [2711245919, 7 | 0];
  const main = v__cps__df_andThenIO_0(
    v__cps__df_andThenIO_4(
      v__cps__df_andThenIO_8(
        v__cps__df_andThenIO_12(
          v__cps__df_andThenIO_16([7, String(v__inl11_x[1]), [5, [0]]], [16]),
          [14]
        ),
        [12]
      ),
      [10]
    ),
    [8]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
