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

  const v_good = [4, 42 | 0];

  const v_bad = [3, [24]];

  const main = (v__inl23_renamedGood =>
    (() => {
      let v__inl25_scrut;
      $join24: {
        const v__inl19_x = v_bad;
        {
          const __s = (s => {
            switch (s[0]) {
              case 3: {
                return [3, [25]];
              }
              case 4: {
                return v__inl19_x;
              }
            }
          })(v__inl19_x);
          switch (__s[0]) {
            case 3: {
              v__inl25_scrut = (s => {
                switch (s[0]) {
                  case 3: {
                    return [4, "bad-Left bad-Left"];
                  }
                  case 4: {
                    return __concat(
                      "bad-Left good-Right ",
                      String(v__inl23_renamedGood[1])
                    );
                  }
                }
              })(v__inl23_renamedGood);
              break $join24;
            }
            case 4: {
              return [7, "WAT", [5, [0]]];
            }
          }
        }
      }
      switch (v__inl25_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl25_scrut[1], [5, [0]]];
        }
      }
    })())(
    (v__inl20_x =>
      (s => {
        switch (s[0]) {
          case 3: {
            return [3, [25]];
          }
          case 4: {
            return v__inl20_x;
          }
        }
      })(v__inl20_x))(v_good)
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
