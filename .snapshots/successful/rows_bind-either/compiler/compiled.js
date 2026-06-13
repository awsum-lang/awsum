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

  const main = (v__inl11_r =>
    (s => {
      switch (s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v__inl13_s = s[1];
          return [7, v__inl13_s, [5, [0]]];
        }
      }
    })(
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl11_r[1];
              switch (__s[0]) {
                case 2269767818: {
                  return [4, "ErrB"];
                }
              }
            }
          }
          case 4: {
            return __concat("Ok ", String(v__inl11_r[1]));
          }
        }
      })(v__inl11_r)
    ))(
    (v__inl4___input =>
      (s => {
        switch (s[0]) {
          case 3: {
            return [3, [2269767818, v__inl4___input[1]]];
          }
          case 4: {
            return v__inl4___input;
          }
        }
      })(v__inl4___input))([3, [25]])
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
