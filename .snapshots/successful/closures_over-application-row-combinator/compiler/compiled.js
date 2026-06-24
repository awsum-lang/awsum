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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_oa = [4, 10 | 0];

  const v_$apply$$scc$$apply1__$rowmono$0$bindEither = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 12: {
          return v_$x;
        }
        case 13: {
          const __t0 = v_$k[1];
          const __t1 = (s => {
            switch (s[0]) {
              case 3: {
                const v_$inl1$____f0 = s[1];
                return (v_$k[0] = 3, v_$k[1] = [
                  2269767818,
                  v_$inl1$____f0
                ], v_$k);
              }
              case 4: {
                return v_$x;
              }
            }
          })(v_$x);
          v_$k = __t0;
          v_$x = __t1;
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$rowmono$0$bindEither = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 10: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 8: {
              v_$args = (v_$args[0] = 11, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 9: {
              return v_$apply$$scc$$apply1__$rowmono$0$bindEither(
                v_$k,
                [4, v_$arg0]
              );
            }
          }
        }
        case 11: {
          const v_x = v_$args[1];
          switch (v_x[0]) {
            case 3: {
              const v_e = v_x[1];
              return v_$apply$$scc$$apply1__$rowmono$0$bindEither(
                v_$k,
                [3, [2252990199, v_e]]
              );
            }
            case 4: {
              const v_a = v_x[1];
              v_$args = (v_$args[0] = 10, v_$args[1] = v_$args[2], v_$args[2] = v_a, v_$args);
              v_$k = [13, v_$k];
              continue;
            }
          }
        }
      }
    }
  };

  const v_result = v_$cps$$scc$$apply1__$rowmono$0$bindEither(
    [10, [8, v_oa], [9]],
    [12]
  );

  const v_$inl7$r = v_result;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v_$inl7$r[1];
            switch (__s[0]) {
              case 2252990199: {
                return "ERR_A";
              }
              case 2269767818: {
                return "ERR_B";
              }
            }
          }
        }
        case 4: {
          return String(v_$inl7$r[1]);
        }
      }
    })(v_$inl7$r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
