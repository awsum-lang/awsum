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

  const v_ok = [4, 10 | 0];

  const main = (v__inl19_mappedOk =>
    (() => {
      let v__inl14_scrut;
      $join13: {
        switch (v__inl19_mappedOk[0]) {
          case 3: {
            return [7, "ok-Err", [5, [0]]];
          }
          case 4: {
            v__inl14_scrut = __concat(
              "ok-Right ",
              String(v__inl19_mappedOk[1])
            );
            break $join13;
          }
        }
      }
      switch (v__inl14_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl14_scrut[1], [5, [0]]];
        }
      }
    })())(v_ok);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
