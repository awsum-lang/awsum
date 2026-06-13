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

  const v_advanceStep = v_x => {
    while (true) {
      switch (v_x[0]) {
        case 24: {
          v_x = [25];
          continue;
        }
        case 25: {
          v_x = [26];
          continue;
        }
        case 26: {
          return "Done!";
        }
      }
    }
  };

  const main = [7, v_advanceStep([24]), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
