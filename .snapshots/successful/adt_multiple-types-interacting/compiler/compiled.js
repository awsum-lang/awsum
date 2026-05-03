"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

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
    return (v__let_1)(((s) => { switch(s[0]) { case 0: { const v__do_e_28_9 = s[1]; return [0, v__do_e_28_9]; } case 1: { const v_s0 = s[1]; return [1, (v_s0 + (v_showResult)([0, [0, [1]]]))]; } } })([1, ((v_showBoxedColor)([0, [0]]) + " ")]));
}

function v__let_1(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return __print("STRING_TOO_LONG");
        }
        case 1: {
          const v_s = __s[1];
          return __print(v_s);
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main([1, arg]);
}

})();