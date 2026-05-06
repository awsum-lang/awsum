"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
          const v_s = __s[1];
          const v_next = __s[2];
          {
            const __s = __print(v_s);
            switch (__s[0]) {
              case 0: {
                const __t0 = v_next;
                v_io = __t0;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v_colorName(v_c){
    {
      const __s = v_c;
      switch (__s[0]) {
        case 0: {
          return "red";
        }
        case 1: {
          return "green";
        }
        case 2: {
          return "blue";
        }
      }
    }
}

function v_showBoxedColor(v_bc){
    {
      const __s = v_bc;
      switch (__s[0]) {
        case 0: {
          const v_c = __s[1];
          return (v_colorName)(v_c);
        }
      }
    }
}

function v_showResult(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v_box = __s[1];
          return (v_showBoxedColor)(v_box);
        }
        case 1: {
          const v_e = __s[1];
          return v_e;
        }
      }
    }
}

function main(v__input){
    return (v__let_2)(((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_s0 = s[1]; return [1, (v_s0 + (v_showResult)([0, [0, [1]]]))]; } } })([1, ((v_showBoxedColor)([0, [0]]) + " ")]));
}

function v__let_2(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main([1, arg]));
}

})();