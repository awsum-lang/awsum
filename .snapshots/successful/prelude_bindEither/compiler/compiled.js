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

  const v_opA = [4, 1 | 0];

  const v__inl9_x = v_opA;
  const v__inl14_chained = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v__inl9_x[1]]];
      }
      case 4: {
        const v__inl6___input = [4, v__inl9_x[1]];
        switch (v__inl6___input[0]) {
          case 3: {
            return [3, [2269767818, v__inl6___input[1]]];
          }
          case 4: {
            return v__inl6___input;
          }
        }
      }
    }
  })(v__inl9_x);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        {
          const __s = v__inl14_chained[1];
          switch (__s[0]) {
            case 2252990199: {
              return [4, "ErrA"];
            }
            case 2269767818: {
              return [4, "ErrB"];
            }
          }
        }
      }
      case 4: {
        return __concat("Ok ", String(v__inl14_chained[1]));
      }
    }
  })(v__inl14_chained);

  const v__apply__df_handleErrorIO_1 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 20: {
          return v__x;
        }
        case 21: {
          const v__pk_21 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_21;
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
          v__k = [21, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_5 = (v__k, v__x) => {
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
          v__k = [23, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl17_x = v_res;
  const main = v__cps__df_handleErrorIO_1(
    v__cps__df_andThenIO_5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl17_x[1]];
          }
          case 4: {
            return [5, v__inl17_x[1]];
          }
        }
      })(v__inl17_x),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
