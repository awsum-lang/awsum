"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_and(v_a, v_b){
    {
      const __s = v_a;
      switch (__s[0]) {
        case 0: {
          return v_b;
        }
        case 1: {
          return [1];
        }
      }
    }
}

function v_showBool(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return "True";
        }
        case 1: {
          return "False";
        }
      }
    }
}

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

function v_un(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 0: {
          return [0];
        }
        case 1: {
          return [0];
        }
        case 2: {
          return [0];
        }
        case 3: {
          return [0];
        }
        case 4: {
          return [0];
        }
        case 5: {
          return [0];
        }
        case 6: {
          return [0];
        }
        case 7: {
          return [0];
        }
        case 8: {
          return [0];
        }
        case 9: {
          return [0];
        }
        case 10: {
          return [0];
        }
        case 11: {
          return [0];
        }
        case 12: {
          return [0];
        }
        case 13: {
          return [0];
        }
        case 14: {
          return [0];
        }
        case 15: {
          return [0];
        }
        case 16: {
          return [0];
        }
        case 17: {
          return [0];
        }
        case 18: {
          return [0];
        }
        case 19: {
          return [0];
        }
        case 20: {
          return [0];
        }
        case 21: {
          return [0];
        }
        case 22: {
          return [0];
        }
        case 23: {
          return [0];
        }
        case 24: {
          return [0];
        }
        case 25: {
          return [0];
        }
        case 26: {
          return [0];
        }
        case 27: {
          return [0];
        }
        case 28: {
          return [0];
        }
        case 29: {
          return [0];
        }
        case 30: {
          return [0];
        }
        case 31: {
          return [0];
        }
        case 32: {
          return [0];
        }
        case 33: {
          return [0];
        }
        case 34: {
          return [0];
        }
        case 35: {
          return [0];
        }
        case 36: {
          return [0];
        }
        case 37: {
          return [0];
        }
        case 38: {
          return [0];
        }
        case 39: {
          return [0];
        }
        case 40: {
          return [0];
        }
        case 41: {
          return [0];
        }
        case 42: {
          return [0];
        }
        case 43: {
          return [0];
        }
        case 44: {
          return [0];
        }
        case 45: {
          return [0];
        }
        case 46: {
          return [0];
        }
        case 47: {
          return [0];
        }
        case 48: {
          return [0];
        }
        case 49: {
          return [0];
        }
        case 50: {
          return [0];
        }
        case 51: {
          return [0];
        }
        case 52: {
          return [0];
        }
        case 53: {
          return [0];
        }
        case 54: {
          return [0];
        }
        case 55: {
          return [0];
        }
        case 56: {
          return [0];
        }
        case 57: {
          return [0];
        }
        case 58: {
          return [0];
        }
        case 59: {
          return [0];
        }
        case 60: {
          return [0];
        }
        case 61: {
          return [0];
        }
        case 62: {
          return [0];
        }
        case 63: {
          return [0];
        }
        case 64: {
          return [0];
        }
        case 65: {
          return [0];
        }
        case 66: {
          return [0];
        }
        case 67: {
          return [0];
        }
        case 68: {
          return [0];
        }
        case 69: {
          return [0];
        }
        case 70: {
          return [0];
        }
        case 71: {
          return [0];
        }
        case 72: {
          return [0];
        }
        case 73: {
          return [0];
        }
        case 74: {
          return [0];
        }
        case 75: {
          return [0];
        }
        case 76: {
          return [0];
        }
        case 77: {
          return [0];
        }
        case 78: {
          return [0];
        }
        case 79: {
          return [0];
        }
        case 80: {
          return [0];
        }
        case 81: {
          return [0];
        }
        case 82: {
          return [0];
        }
        case 83: {
          return [0];
        }
        case 84: {
          return [0];
        }
        case 85: {
          return [0];
        }
        case 86: {
          return [0];
        }
        case 87: {
          return [0];
        }
        case 88: {
          return [0];
        }
        case 89: {
          return [0];
        }
        case 90: {
          return [0];
        }
        case 91: {
          return [0];
        }
        case 92: {
          return [0];
        }
        case 93: {
          return [0];
        }
        case 94: {
          return [0];
        }
        case 95: {
          return [0];
        }
        case 96: {
          return [0];
        }
        case 97: {
          return [0];
        }
        case 98: {
          return [0];
        }
        case 99: {
          return [0];
        }
        case 100: {
          return [0];
        }
        case 101: {
          return [0];
        }
        case 102: {
          return [0];
        }
        case 103: {
          return [0];
        }
        case 104: {
          return [0];
        }
        case 105: {
          return [0];
        }
        case 106: {
          return [0];
        }
        case 107: {
          return [0];
        }
        case 108: {
          return [0];
        }
        case 109: {
          return [0];
        }
        case 110: {
          return [0];
        }
        case 111: {
          return [0];
        }
        case 112: {
          return [0];
        }
        case 113: {
          return [0];
        }
        case 114: {
          return [0];
        }
        case 115: {
          return [0];
        }
        case 116: {
          return [0];
        }
        case 117: {
          return [0];
        }
        case 118: {
          return [0];
        }
        case 119: {
          return [0];
        }
        case 120: {
          return [0];
        }
        case 121: {
          return [0];
        }
        case 122: {
          return [0];
        }
        case 123: {
          return [0];
        }
        case 124: {
          return [0];
        }
        case 125: {
          return [0];
        }
        case 126: {
          return [0];
        }
        case 127: {
          return [0];
        }
        case 128: {
          return [0];
        }
        case 129: {
          return [0];
        }
        case 130: {
          return [0];
        }
        case 131: {
          return [0];
        }
        case 132: {
          return [0];
        }
        case 133: {
          return [0];
        }
        case 134: {
          return [0];
        }
        case 135: {
          return [0];
        }
        case 136: {
          return [0];
        }
        case 137: {
          return [0];
        }
        case 138: {
          return [0];
        }
        case 139: {
          return [0];
        }
        case 140: {
          return [0];
        }
        case 141: {
          return [0];
        }
        case 142: {
          return [0];
        }
        case 143: {
          return [0];
        }
        case 144: {
          return [0];
        }
        case 145: {
          return [0];
        }
        case 146: {
          return [0];
        }
        case 147: {
          return [0];
        }
        case 148: {
          return [0];
        }
        case 149: {
          return [0];
        }
        case 150: {
          return [0];
        }
        case 151: {
          return [0];
        }
        case 152: {
          return [0];
        }
        case 153: {
          return [0];
        }
        case 154: {
          return [0];
        }
        case 155: {
          return [0];
        }
        case 156: {
          return [0];
        }
        case 157: {
          return [0];
        }
        case 158: {
          return [0];
        }
        case 159: {
          return [0];
        }
        case 160: {
          return [0];
        }
        case 161: {
          return [0];
        }
        case 162: {
          return [0];
        }
        case 163: {
          return [0];
        }
        case 164: {
          return [0];
        }
        case 165: {
          return [0];
        }
        case 166: {
          return [0];
        }
        case 167: {
          return [0];
        }
        case 168: {
          return [0];
        }
        case 169: {
          return [0];
        }
        case 170: {
          return [0];
        }
        case 171: {
          return [0];
        }
        case 172: {
          return [0];
        }
        case 173: {
          return [0];
        }
        case 174: {
          return [0];
        }
        case 175: {
          return [0];
        }
        case 176: {
          return [0];
        }
        case 177: {
          return [0];
        }
        case 178: {
          return [0];
        }
        case 179: {
          return [0];
        }
        case 180: {
          return [0];
        }
        case 181: {
          return [0];
        }
        case 182: {
          return [0];
        }
        case 183: {
          return [0];
        }
        case 184: {
          return [0];
        }
        case 185: {
          return [0];
        }
        case 186: {
          return [0];
        }
        case 187: {
          return [0];
        }
        case 188: {
          return [0];
        }
        case 189: {
          return [0];
        }
        case 190: {
          return [0];
        }
        case 191: {
          return [0];
        }
        case 192: {
          return [0];
        }
        case 193: {
          return [0];
        }
        case 194: {
          return [0];
        }
        case 195: {
          return [0];
        }
        case 196: {
          return [0];
        }
        case 197: {
          return [0];
        }
        case 198: {
          return [0];
        }
        case 199: {
          return [0];
        }
        case 200: {
          return [0];
        }
        case 201: {
          return [0];
        }
        case 202: {
          return [0];
        }
        case 203: {
          return [0];
        }
        case 204: {
          return [0];
        }
        case 205: {
          return [0];
        }
        case 206: {
          return [0];
        }
        case 207: {
          return [0];
        }
        case 208: {
          return [0];
        }
        case 209: {
          return [0];
        }
        case 210: {
          return [0];
        }
        case 211: {
          return [0];
        }
        case 212: {
          return [0];
        }
        case 213: {
          return [0];
        }
        case 214: {
          return [0];
        }
        case 215: {
          return [0];
        }
        case 216: {
          return [0];
        }
        case 217: {
          return [0];
        }
        case 218: {
          return [0];
        }
        case 219: {
          return [0];
        }
        case 220: {
          return [0];
        }
        case 221: {
          return [0];
        }
        case 222: {
          return [0];
        }
        case 223: {
          return [0];
        }
        case 224: {
          return [0];
        }
        case 225: {
          return [0];
        }
        case 226: {
          return [0];
        }
        case 227: {
          return [0];
        }
        case 228: {
          return [0];
        }
        case 229: {
          return [0];
        }
        case 230: {
          return [0];
        }
        case 231: {
          return [0];
        }
        case 232: {
          return [0];
        }
        case 233: {
          return [0];
        }
        case 234: {
          return [0];
        }
        case 235: {
          return [0];
        }
        case 236: {
          return [0];
        }
        case 237: {
          return [0];
        }
        case 238: {
          return [0];
        }
        case 239: {
          return [0];
        }
        case 240: {
          return [0];
        }
        case 241: {
          return [0];
        }
        case 242: {
          return [0];
        }
        case 243: {
          return [0];
        }
        case 244: {
          return [0];
        }
        case 245: {
          return [0];
        }
        case 246: {
          return [0];
        }
        case 247: {
          return [0];
        }
        case 248: {
          return [0];
        }
        case 249: {
          return [0];
        }
        case 250: {
          return [0];
        }
        case 251: {
          return [0];
        }
        case 252: {
          return [0];
        }
        case 253: {
          return [0];
        }
        case 254: {
          return [0];
        }
        case 255: {
          return [0];
        }
        case 256: {
          return [0];
        }
        case 257: {
          return [0];
        }
        case 258: {
          return [0];
        }
        case 259: {
          return [0];
        }
        case 260: {
          return [0];
        }
        case 261: {
          return [0];
        }
        case 262: {
          return [0];
        }
        case 263: {
          return [0];
        }
        case 264: {
          return [0];
        }
        case 265: {
          return [0];
        }
        case 266: {
          return [0];
        }
        case 267: {
          return [0];
        }
        case 268: {
          return [0];
        }
        case 269: {
          return [0];
        }
        case 270: {
          return [0];
        }
        case 271: {
          return [0];
        }
        case 272: {
          return [0];
        }
        case 273: {
          return [0];
        }
        case 274: {
          return [0];
        }
        case 275: {
          return [0];
        }
        case 276: {
          return [0];
        }
        case 277: {
          return [0];
        }
        case 278: {
          return [0];
        }
        case 279: {
          return [0];
        }
        case 280: {
          return [0];
        }
        case 281: {
          return [0];
        }
        case 282: {
          return [0];
        }
        case 283: {
          return [0];
        }
        case 284: {
          return [0];
        }
        case 285: {
          return [0];
        }
        case 286: {
          return [0];
        }
        case 287: {
          return [0];
        }
        case 288: {
          return [0];
        }
        case 289: {
          return [0];
        }
        case 290: {
          return [0];
        }
        case 291: {
          return [0];
        }
        case 292: {
          return [0];
        }
        case 293: {
          return [0];
        }
        case 294: {
          return [0];
        }
        case 295: {
          return [0];
        }
        case 296: {
          return [0];
        }
        case 297: {
          return [0];
        }
        case 298: {
          return [0];
        }
        case 299: {
          return [0];
        }
      }
    }
}

const v_res = (v_and)((v_un)([0]), (v_and)((v_un)([1]), (v_and)((v_un)([2]), (v_and)((v_un)([3]), (v_and)((v_un)([4]), (v_and)((v_un)([5]), (v_and)((v_un)([6]), (v_and)((v_un)([7]), (v_and)((v_un)([8]), (v_and)((v_un)([9]), (v_and)((v_un)([10]), (v_and)((v_un)([11]), (v_and)((v_un)([12]), (v_and)((v_un)([13]), (v_and)((v_un)([14]), (v_and)((v_un)([15]), (v_and)((v_un)([16]), (v_and)((v_un)([17]), (v_and)((v_un)([18]), (v_and)((v_un)([19]), (v_and)((v_un)([20]), (v_and)((v_un)([21]), (v_and)((v_un)([22]), (v_and)((v_un)([23]), (v_and)((v_un)([24]), (v_and)((v_un)([25]), (v_and)((v_un)([26]), (v_and)((v_un)([27]), (v_and)((v_un)([28]), (v_and)((v_un)([29]), (v_and)((v_un)([30]), (v_and)((v_un)([31]), (v_and)((v_un)([32]), (v_and)((v_un)([33]), (v_and)((v_un)([34]), (v_and)((v_un)([35]), (v_and)((v_un)([36]), (v_and)((v_un)([37]), (v_and)((v_un)([38]), (v_and)((v_un)([39]), (v_and)((v_un)([40]), (v_and)((v_un)([41]), (v_and)((v_un)([42]), (v_and)((v_un)([43]), (v_and)((v_un)([44]), (v_and)((v_un)([45]), (v_and)((v_un)([46]), (v_and)((v_un)([47]), (v_and)((v_un)([48]), (v_and)((v_un)([49]), (v_and)((v_un)([50]), (v_and)((v_un)([51]), (v_and)((v_un)([52]), (v_and)((v_un)([53]), (v_and)((v_un)([54]), (v_and)((v_un)([55]), (v_and)((v_un)([56]), (v_and)((v_un)([57]), (v_and)((v_un)([58]), (v_and)((v_un)([59]), (v_and)((v_un)([60]), (v_and)((v_un)([61]), (v_and)((v_un)([62]), (v_and)((v_un)([63]), (v_and)((v_un)([64]), (v_and)((v_un)([65]), (v_and)((v_un)([66]), (v_and)((v_un)([67]), (v_and)((v_un)([68]), (v_and)((v_un)([69]), (v_and)((v_un)([70]), (v_and)((v_un)([71]), (v_and)((v_un)([72]), (v_and)((v_un)([73]), (v_and)((v_un)([74]), (v_and)((v_un)([75]), (v_and)((v_un)([76]), (v_and)((v_un)([77]), (v_and)((v_un)([78]), (v_and)((v_un)([79]), (v_and)((v_un)([80]), (v_and)((v_un)([81]), (v_and)((v_un)([82]), (v_and)((v_un)([83]), (v_and)((v_un)([84]), (v_and)((v_un)([85]), (v_and)((v_un)([86]), (v_and)((v_un)([87]), (v_and)((v_un)([88]), (v_and)((v_un)([89]), (v_and)((v_un)([90]), (v_and)((v_un)([91]), (v_and)((v_un)([92]), (v_and)((v_un)([93]), (v_and)((v_un)([94]), (v_and)((v_un)([95]), (v_and)((v_un)([96]), (v_and)((v_un)([97]), (v_and)((v_un)([98]), (v_and)((v_un)([99]), (v_and)((v_un)([100]), (v_and)((v_un)([101]), (v_and)((v_un)([102]), (v_and)((v_un)([103]), (v_and)((v_un)([104]), (v_and)((v_un)([105]), (v_and)((v_un)([106]), (v_and)((v_un)([107]), (v_and)((v_un)([108]), (v_and)((v_un)([109]), (v_and)((v_un)([110]), (v_and)((v_un)([111]), (v_and)((v_un)([112]), (v_and)((v_un)([113]), (v_and)((v_un)([114]), (v_and)((v_un)([115]), (v_and)((v_un)([116]), (v_and)((v_un)([117]), (v_and)((v_un)([118]), (v_and)((v_un)([119]), (v_and)((v_un)([120]), (v_and)((v_un)([121]), (v_and)((v_un)([122]), (v_and)((v_un)([123]), (v_and)((v_un)([124]), (v_and)((v_un)([125]), (v_and)((v_un)([126]), (v_and)((v_un)([127]), (v_and)((v_un)([128]), (v_and)((v_un)([129]), (v_and)((v_un)([130]), (v_and)((v_un)([131]), (v_and)((v_un)([132]), (v_and)((v_un)([133]), (v_and)((v_un)([134]), (v_and)((v_un)([135]), (v_and)((v_un)([136]), (v_and)((v_un)([137]), (v_and)((v_un)([138]), (v_and)((v_un)([139]), (v_and)((v_un)([140]), (v_and)((v_un)([141]), (v_and)((v_un)([142]), (v_and)((v_un)([143]), (v_and)((v_un)([144]), (v_and)((v_un)([145]), (v_and)((v_un)([146]), (v_and)((v_un)([147]), (v_and)((v_un)([148]), (v_and)((v_un)([149]), (v_and)((v_un)([150]), (v_and)((v_un)([151]), (v_and)((v_un)([152]), (v_and)((v_un)([153]), (v_and)((v_un)([154]), (v_and)((v_un)([155]), (v_and)((v_un)([156]), (v_and)((v_un)([157]), (v_and)((v_un)([158]), (v_and)((v_un)([159]), (v_and)((v_un)([160]), (v_and)((v_un)([161]), (v_and)((v_un)([162]), (v_and)((v_un)([163]), (v_and)((v_un)([164]), (v_and)((v_un)([165]), (v_and)((v_un)([166]), (v_and)((v_un)([167]), (v_and)((v_un)([168]), (v_and)((v_un)([169]), (v_and)((v_un)([170]), (v_and)((v_un)([171]), (v_and)((v_un)([172]), (v_and)((v_un)([173]), (v_and)((v_un)([174]), (v_and)((v_un)([175]), (v_and)((v_un)([176]), (v_and)((v_un)([177]), (v_and)((v_un)([178]), (v_and)((v_un)([179]), (v_and)((v_un)([180]), (v_and)((v_un)([181]), (v_and)((v_un)([182]), (v_and)((v_un)([183]), (v_and)((v_un)([184]), (v_and)((v_un)([185]), (v_and)((v_un)([186]), (v_and)((v_un)([187]), (v_and)((v_un)([188]), (v_and)((v_un)([189]), (v_and)((v_un)([190]), (v_and)((v_un)([191]), (v_and)((v_un)([192]), (v_and)((v_un)([193]), (v_and)((v_un)([194]), (v_and)((v_un)([195]), (v_and)((v_un)([196]), (v_and)((v_un)([197]), (v_and)((v_un)([198]), (v_and)((v_un)([199]), (v_and)((v_un)([200]), (v_and)((v_un)([201]), (v_and)((v_un)([202]), (v_and)((v_un)([203]), (v_and)((v_un)([204]), (v_and)((v_un)([205]), (v_and)((v_un)([206]), (v_and)((v_un)([207]), (v_and)((v_un)([208]), (v_and)((v_un)([209]), (v_and)((v_un)([210]), (v_and)((v_un)([211]), (v_and)((v_un)([212]), (v_and)((v_un)([213]), (v_and)((v_un)([214]), (v_and)((v_un)([215]), (v_and)((v_un)([216]), (v_and)((v_un)([217]), (v_and)((v_un)([218]), (v_and)((v_un)([219]), (v_and)((v_un)([220]), (v_and)((v_un)([221]), (v_and)((v_un)([222]), (v_and)((v_un)([223]), (v_and)((v_un)([224]), (v_and)((v_un)([225]), (v_and)((v_un)([226]), (v_and)((v_un)([227]), (v_and)((v_un)([228]), (v_and)((v_un)([229]), (v_and)((v_un)([230]), (v_and)((v_un)([231]), (v_and)((v_un)([232]), (v_and)((v_un)([233]), (v_and)((v_un)([234]), (v_and)((v_un)([235]), (v_and)((v_un)([236]), (v_and)((v_un)([237]), (v_and)((v_un)([238]), (v_and)((v_un)([239]), (v_and)((v_un)([240]), (v_and)((v_un)([241]), (v_and)((v_un)([242]), (v_and)((v_un)([243]), (v_and)((v_un)([244]), (v_and)((v_un)([245]), (v_and)((v_un)([246]), (v_and)((v_un)([247]), (v_and)((v_un)([248]), (v_and)((v_un)([249]), (v_and)((v_un)([250]), (v_and)((v_un)([251]), (v_and)((v_un)([252]), (v_and)((v_un)([253]), (v_and)((v_un)([254]), (v_and)((v_un)([255]), (v_and)((v_un)([256]), (v_and)((v_un)([257]), (v_and)((v_un)([258]), (v_and)((v_un)([259]), (v_and)((v_un)([260]), (v_and)((v_un)([261]), (v_and)((v_un)([262]), (v_and)((v_un)([263]), (v_and)((v_un)([264]), (v_and)((v_un)([265]), (v_and)((v_un)([266]), (v_and)((v_un)([267]), (v_and)((v_un)([268]), (v_and)((v_un)([269]), (v_and)((v_un)([270]), (v_and)((v_un)([271]), (v_and)((v_un)([272]), (v_and)((v_un)([273]), (v_and)((v_un)([274]), (v_and)((v_un)([275]), (v_and)((v_un)([276]), (v_and)((v_un)([277]), (v_and)((v_un)([278]), (v_and)((v_un)([279]), (v_and)((v_un)([280]), (v_and)((v_un)([281]), (v_and)((v_un)([282]), (v_and)((v_un)([283]), (v_and)((v_un)([284]), (v_and)((v_un)([285]), (v_and)((v_un)([286]), (v_and)((v_un)([287]), (v_and)((v_un)([288]), (v_and)((v_un)([289]), (v_and)((v_un)([290]), (v_and)((v_un)([291]), (v_and)((v_un)([292]), (v_and)((v_un)([293]), (v_and)((v_un)([294]), (v_and)((v_un)([295]), (v_and)((v_un)([296]), (v_and)((v_un)([297]), (v_and)((v_un)([298]), (v_un)([299]))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))));

function main(v__input){
    return [2, (v_showBool)(v_res), [0, [0]]];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();