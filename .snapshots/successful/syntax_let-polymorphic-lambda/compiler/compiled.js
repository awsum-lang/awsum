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

  const main = (() => {
    let v__inl16_scrut;
    $join15: {
      const __s = __concat(String(42 | 0), "/");
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v__inl8_s0 = __s[1];
          v__inl16_scrut = (s => {
            switch (s[0]) {
              case 3: {
                const v__inl9__do_e_1 = s[1];
                return [3, v__inl9__do_e_1];
              }
              case 4: {
                const v__inl10_s1 = s[1];
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
          })(__concat(v__inl8_s0, "hello"));
          break $join15;
        }
      }
    }
    switch (v__inl16_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl16_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
