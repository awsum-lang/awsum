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

  const v_res = [3, [348914022, [25]]];

  const main = [
    7,
    (v__inl7_r =>
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl7_r[1];
              switch (__s[0]) {
                case 348914022: {
                  return "B";
                }
              }
            }
          }
          case 4: {
            return String(v__inl7_r[1]);
          }
        }
      })(v__inl7_r))(v_res),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
