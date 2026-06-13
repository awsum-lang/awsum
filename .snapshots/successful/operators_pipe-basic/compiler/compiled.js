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

  const v_n = 42 | 0;

  const v_viaLambda = String(v_n);

  const v_chained = String(v_n);

  const v_basic = String(v_n);

  const v_joined = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_2 = s[1];
        return [3, v__do_e_2];
      }
      case 4: {
        const v_a = s[1];
        {
          const __s = __concat(v_a, v_chained);
          switch (__s[0]) {
            case 3: {
              const v__do_e_1 = __s[1];
              return [3, v__do_e_1];
            }
            case 4: {
              const v_b = __s[1];
              {
                const __s = __concat(v_b, "|");
                switch (__s[0]) {
                  case 3: {
                    const v__do_e_0 = __s[1];
                    return [3, v__do_e_0];
                  }
                  case 4: {
                    const v_c = __s[1];
                    return __concat(v_c, v_viaLambda);
                  }
                }
              }
            }
          }
        }
      }
    }
  })(__concat(v_basic, "|"));

  const main = (s => {
    switch (s[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        const v_s = s[1];
        return [7, v_s, [5, [0]]];
      }
    }
  })(v_joined);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
