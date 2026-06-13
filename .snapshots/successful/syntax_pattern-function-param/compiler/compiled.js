"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_triple = [16, 10 | 0, 20 | 0, 30 | 0];

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

  const v_pair = [15, 100 | 0, 200 | 0];

  const main = (() => {
    let v__inl24_scrut;
    $join23: {
      const __s = __concat(
        String(
          (v__inl22__arg_0 =>
            (s => {
              switch (s[0]) {
                case 3: {
                  return 0 | 0;
                }
                case 4: {
                  const v__inl19_ab = s[1];
                  {
                    const __s = __addInt32(v__inl19_ab, v__inl22__arg_0[3]);
                    switch (__s[0]) {
                      case 3: {
                        return 0 | 0;
                      }
                      case 4: {
                        const v__inl21_abc = __s[1];
                        return v__inl21_abc;
                      }
                    }
                  }
                }
              }
            })(__addInt32(v__inl22__arg_0[1], v__inl22__arg_0[2])))(v_triple)
        ),
        " / "
      );
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v__inl28_s0 = __s[1];
          v__inl24_scrut = __concat(
            v__inl28_s0,
            String(
              (v__inl29_t =>
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return 0 | 0;
                    }
                    case 4: {
                      const v__inl31_s = s[1];
                      return v__inl31_s;
                    }
                  }
                })(__addInt32(v__inl29_t[1], v__inl29_t[2])))(v_pair)
            )
          );
          break $join23;
        }
      }
    }
    switch (v__inl24_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl24_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
