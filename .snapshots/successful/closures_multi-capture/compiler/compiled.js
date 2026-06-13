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
    let v__inl12_scrut;
    $join11: {
      const __s = __concat(String(11 | 0), "/");
      switch (__s[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v__inl8_s0 = __s[1];
          v__inl12_scrut = __concat(v__inl8_s0, String(22 | 0));
          break $join11;
        }
      }
    }
    switch (v__inl12_scrut[0]) {
      case 3: {
        return [7, "STRING_TOO_LONG", [5, [0]]];
      }
      case 4: {
        return [7, v__inl12_scrut[1], [5, [0]]];
      }
    }
  })();

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
