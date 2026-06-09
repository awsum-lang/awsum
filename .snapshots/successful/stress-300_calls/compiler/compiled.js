"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_showBool = v_b => {
    {
      const __s = v_b;
      switch (__s[0]) {
        case 1: {
          return "True";
        }
        case 2: {
          return "False";
        }
      }
    }
  };

  const v_runIO = v_io => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
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
  };

  const v_and = (v_a, v_b) => {
    {
      const __s = v_a;
      switch (__s[0]) {
        case 1: {
          return v_b;
        }
        case 2: {
          return [2];
        }
      }
    }
  };

  const v_f300 = v_acc => v_and(v_acc, [1]);

  const v_f299 = v_acc => v_f300(v_and(v_acc, [1]));

  const v_f298 = v_acc => v_f299(v_and(v_acc, [1]));

  const v_f297 = v_acc => v_f298(v_and(v_acc, [1]));

  const v_f296 = v_acc => v_f297(v_and(v_acc, [1]));

  const v_f295 = v_acc => v_f296(v_and(v_acc, [1]));

  const v_f294 = v_acc => v_f295(v_and(v_acc, [1]));

  const v_f293 = v_acc => v_f294(v_and(v_acc, [1]));

  const v_f292 = v_acc => v_f293(v_and(v_acc, [1]));

  const v_f291 = v_acc => v_f292(v_and(v_acc, [1]));

  const v_f290 = v_acc => v_f291(v_and(v_acc, [1]));

  const v_f289 = v_acc => v_f290(v_and(v_acc, [1]));

  const v_f288 = v_acc => v_f289(v_and(v_acc, [1]));

  const v_f287 = v_acc => v_f288(v_and(v_acc, [1]));

  const v_f286 = v_acc => v_f287(v_and(v_acc, [1]));

  const v_f285 = v_acc => v_f286(v_and(v_acc, [1]));

  const v_f284 = v_acc => v_f285(v_and(v_acc, [1]));

  const v_f283 = v_acc => v_f284(v_and(v_acc, [1]));

  const v_f282 = v_acc => v_f283(v_and(v_acc, [1]));

  const v_f281 = v_acc => v_f282(v_and(v_acc, [1]));

  const v_f280 = v_acc => v_f281(v_and(v_acc, [1]));

  const v_f279 = v_acc => v_f280(v_and(v_acc, [1]));

  const v_f278 = v_acc => v_f279(v_and(v_acc, [1]));

  const v_f277 = v_acc => v_f278(v_and(v_acc, [1]));

  const v_f276 = v_acc => v_f277(v_and(v_acc, [1]));

  const v_f275 = v_acc => v_f276(v_and(v_acc, [1]));

  const v_f274 = v_acc => v_f275(v_and(v_acc, [1]));

  const v_f273 = v_acc => v_f274(v_and(v_acc, [1]));

  const v_f272 = v_acc => v_f273(v_and(v_acc, [1]));

  const v_f271 = v_acc => v_f272(v_and(v_acc, [1]));

  const v_f270 = v_acc => v_f271(v_and(v_acc, [1]));

  const v_f269 = v_acc => v_f270(v_and(v_acc, [1]));

  const v_f268 = v_acc => v_f269(v_and(v_acc, [1]));

  const v_f267 = v_acc => v_f268(v_and(v_acc, [1]));

  const v_f266 = v_acc => v_f267(v_and(v_acc, [1]));

  const v_f265 = v_acc => v_f266(v_and(v_acc, [1]));

  const v_f264 = v_acc => v_f265(v_and(v_acc, [1]));

  const v_f263 = v_acc => v_f264(v_and(v_acc, [1]));

  const v_f262 = v_acc => v_f263(v_and(v_acc, [1]));

  const v_f261 = v_acc => v_f262(v_and(v_acc, [1]));

  const v_f260 = v_acc => v_f261(v_and(v_acc, [1]));

  const v_f259 = v_acc => v_f260(v_and(v_acc, [1]));

  const v_f258 = v_acc => v_f259(v_and(v_acc, [1]));

  const v_f257 = v_acc => v_f258(v_and(v_acc, [1]));

  const v_f256 = v_acc => v_f257(v_and(v_acc, [1]));

  const v_f255 = v_acc => v_f256(v_and(v_acc, [1]));

  const v_f254 = v_acc => v_f255(v_and(v_acc, [1]));

  const v_f253 = v_acc => v_f254(v_and(v_acc, [1]));

  const v_f252 = v_acc => v_f253(v_and(v_acc, [1]));

  const v_f251 = v_acc => v_f252(v_and(v_acc, [1]));

  const v_f250 = v_acc => v_f251(v_and(v_acc, [1]));

  const v_f249 = v_acc => v_f250(v_and(v_acc, [1]));

  const v_f248 = v_acc => v_f249(v_and(v_acc, [1]));

  const v_f247 = v_acc => v_f248(v_and(v_acc, [1]));

  const v_f246 = v_acc => v_f247(v_and(v_acc, [1]));

  const v_f245 = v_acc => v_f246(v_and(v_acc, [1]));

  const v_f244 = v_acc => v_f245(v_and(v_acc, [1]));

  const v_f243 = v_acc => v_f244(v_and(v_acc, [1]));

  const v_f242 = v_acc => v_f243(v_and(v_acc, [1]));

  const v_f241 = v_acc => v_f242(v_and(v_acc, [1]));

  const v_f240 = v_acc => v_f241(v_and(v_acc, [1]));

  const v_f239 = v_acc => v_f240(v_and(v_acc, [1]));

  const v_f238 = v_acc => v_f239(v_and(v_acc, [1]));

  const v_f237 = v_acc => v_f238(v_and(v_acc, [1]));

  const v_f236 = v_acc => v_f237(v_and(v_acc, [1]));

  const v_f235 = v_acc => v_f236(v_and(v_acc, [1]));

  const v_f234 = v_acc => v_f235(v_and(v_acc, [1]));

  const v_f233 = v_acc => v_f234(v_and(v_acc, [1]));

  const v_f232 = v_acc => v_f233(v_and(v_acc, [1]));

  const v_f231 = v_acc => v_f232(v_and(v_acc, [1]));

  const v_f230 = v_acc => v_f231(v_and(v_acc, [1]));

  const v_f229 = v_acc => v_f230(v_and(v_acc, [1]));

  const v_f228 = v_acc => v_f229(v_and(v_acc, [1]));

  const v_f227 = v_acc => v_f228(v_and(v_acc, [1]));

  const v_f226 = v_acc => v_f227(v_and(v_acc, [1]));

  const v_f225 = v_acc => v_f226(v_and(v_acc, [1]));

  const v_f224 = v_acc => v_f225(v_and(v_acc, [1]));

  const v_f223 = v_acc => v_f224(v_and(v_acc, [1]));

  const v_f222 = v_acc => v_f223(v_and(v_acc, [1]));

  const v_f221 = v_acc => v_f222(v_and(v_acc, [1]));

  const v_f220 = v_acc => v_f221(v_and(v_acc, [1]));

  const v_f219 = v_acc => v_f220(v_and(v_acc, [1]));

  const v_f218 = v_acc => v_f219(v_and(v_acc, [1]));

  const v_f217 = v_acc => v_f218(v_and(v_acc, [1]));

  const v_f216 = v_acc => v_f217(v_and(v_acc, [1]));

  const v_f215 = v_acc => v_f216(v_and(v_acc, [1]));

  const v_f214 = v_acc => v_f215(v_and(v_acc, [1]));

  const v_f213 = v_acc => v_f214(v_and(v_acc, [1]));

  const v_f212 = v_acc => v_f213(v_and(v_acc, [1]));

  const v_f211 = v_acc => v_f212(v_and(v_acc, [1]));

  const v_f210 = v_acc => v_f211(v_and(v_acc, [1]));

  const v_f209 = v_acc => v_f210(v_and(v_acc, [1]));

  const v_f208 = v_acc => v_f209(v_and(v_acc, [1]));

  const v_f207 = v_acc => v_f208(v_and(v_acc, [1]));

  const v_f206 = v_acc => v_f207(v_and(v_acc, [1]));

  const v_f205 = v_acc => v_f206(v_and(v_acc, [1]));

  const v_f204 = v_acc => v_f205(v_and(v_acc, [1]));

  const v_f203 = v_acc => v_f204(v_and(v_acc, [1]));

  const v_f202 = v_acc => v_f203(v_and(v_acc, [1]));

  const v_f201 = v_acc => v_f202(v_and(v_acc, [1]));

  const v_f200 = v_acc => v_f201(v_and(v_acc, [1]));

  const v_f199 = v_acc => v_f200(v_and(v_acc, [1]));

  const v_f198 = v_acc => v_f199(v_and(v_acc, [1]));

  const v_f197 = v_acc => v_f198(v_and(v_acc, [1]));

  const v_f196 = v_acc => v_f197(v_and(v_acc, [1]));

  const v_f195 = v_acc => v_f196(v_and(v_acc, [1]));

  const v_f194 = v_acc => v_f195(v_and(v_acc, [1]));

  const v_f193 = v_acc => v_f194(v_and(v_acc, [1]));

  const v_f192 = v_acc => v_f193(v_and(v_acc, [1]));

  const v_f191 = v_acc => v_f192(v_and(v_acc, [1]));

  const v_f190 = v_acc => v_f191(v_and(v_acc, [1]));

  const v_f189 = v_acc => v_f190(v_and(v_acc, [1]));

  const v_f188 = v_acc => v_f189(v_and(v_acc, [1]));

  const v_f187 = v_acc => v_f188(v_and(v_acc, [1]));

  const v_f186 = v_acc => v_f187(v_and(v_acc, [1]));

  const v_f185 = v_acc => v_f186(v_and(v_acc, [1]));

  const v_f184 = v_acc => v_f185(v_and(v_acc, [1]));

  const v_f183 = v_acc => v_f184(v_and(v_acc, [1]));

  const v_f182 = v_acc => v_f183(v_and(v_acc, [1]));

  const v_f181 = v_acc => v_f182(v_and(v_acc, [1]));

  const v_f180 = v_acc => v_f181(v_and(v_acc, [1]));

  const v_f179 = v_acc => v_f180(v_and(v_acc, [1]));

  const v_f178 = v_acc => v_f179(v_and(v_acc, [1]));

  const v_f177 = v_acc => v_f178(v_and(v_acc, [1]));

  const v_f176 = v_acc => v_f177(v_and(v_acc, [1]));

  const v_f175 = v_acc => v_f176(v_and(v_acc, [1]));

  const v_f174 = v_acc => v_f175(v_and(v_acc, [1]));

  const v_f173 = v_acc => v_f174(v_and(v_acc, [1]));

  const v_f172 = v_acc => v_f173(v_and(v_acc, [1]));

  const v_f171 = v_acc => v_f172(v_and(v_acc, [1]));

  const v_f170 = v_acc => v_f171(v_and(v_acc, [1]));

  const v_f169 = v_acc => v_f170(v_and(v_acc, [1]));

  const v_f168 = v_acc => v_f169(v_and(v_acc, [1]));

  const v_f167 = v_acc => v_f168(v_and(v_acc, [1]));

  const v_f166 = v_acc => v_f167(v_and(v_acc, [1]));

  const v_f165 = v_acc => v_f166(v_and(v_acc, [1]));

  const v_f164 = v_acc => v_f165(v_and(v_acc, [1]));

  const v_f163 = v_acc => v_f164(v_and(v_acc, [1]));

  const v_f162 = v_acc => v_f163(v_and(v_acc, [1]));

  const v_f161 = v_acc => v_f162(v_and(v_acc, [1]));

  const v_f160 = v_acc => v_f161(v_and(v_acc, [1]));

  const v_f159 = v_acc => v_f160(v_and(v_acc, [1]));

  const v_f158 = v_acc => v_f159(v_and(v_acc, [1]));

  const v_f157 = v_acc => v_f158(v_and(v_acc, [1]));

  const v_f156 = v_acc => v_f157(v_and(v_acc, [1]));

  const v_f155 = v_acc => v_f156(v_and(v_acc, [1]));

  const v_f154 = v_acc => v_f155(v_and(v_acc, [1]));

  const v_f153 = v_acc => v_f154(v_and(v_acc, [1]));

  const v_f152 = v_acc => v_f153(v_and(v_acc, [1]));

  const v_f151 = v_acc => v_f152(v_and(v_acc, [1]));

  const v_f150 = v_acc => v_f151(v_and(v_acc, [1]));

  const v_f149 = v_acc => v_f150(v_and(v_acc, [1]));

  const v_f148 = v_acc => v_f149(v_and(v_acc, [1]));

  const v_f147 = v_acc => v_f148(v_and(v_acc, [1]));

  const v_f146 = v_acc => v_f147(v_and(v_acc, [1]));

  const v_f145 = v_acc => v_f146(v_and(v_acc, [1]));

  const v_f144 = v_acc => v_f145(v_and(v_acc, [1]));

  const v_f143 = v_acc => v_f144(v_and(v_acc, [1]));

  const v_f142 = v_acc => v_f143(v_and(v_acc, [1]));

  const v_f141 = v_acc => v_f142(v_and(v_acc, [1]));

  const v_f140 = v_acc => v_f141(v_and(v_acc, [1]));

  const v_f139 = v_acc => v_f140(v_and(v_acc, [1]));

  const v_f138 = v_acc => v_f139(v_and(v_acc, [1]));

  const v_f137 = v_acc => v_f138(v_and(v_acc, [1]));

  const v_f136 = v_acc => v_f137(v_and(v_acc, [1]));

  const v_f135 = v_acc => v_f136(v_and(v_acc, [1]));

  const v_f134 = v_acc => v_f135(v_and(v_acc, [1]));

  const v_f133 = v_acc => v_f134(v_and(v_acc, [1]));

  const v_f132 = v_acc => v_f133(v_and(v_acc, [1]));

  const v_f131 = v_acc => v_f132(v_and(v_acc, [1]));

  const v_f130 = v_acc => v_f131(v_and(v_acc, [1]));

  const v_f129 = v_acc => v_f130(v_and(v_acc, [1]));

  const v_f128 = v_acc => v_f129(v_and(v_acc, [1]));

  const v_f127 = v_acc => v_f128(v_and(v_acc, [1]));

  const v_f126 = v_acc => v_f127(v_and(v_acc, [1]));

  const v_f125 = v_acc => v_f126(v_and(v_acc, [1]));

  const v_f124 = v_acc => v_f125(v_and(v_acc, [1]));

  const v_f123 = v_acc => v_f124(v_and(v_acc, [1]));

  const v_f122 = v_acc => v_f123(v_and(v_acc, [1]));

  const v_f121 = v_acc => v_f122(v_and(v_acc, [1]));

  const v_f120 = v_acc => v_f121(v_and(v_acc, [1]));

  const v_f119 = v_acc => v_f120(v_and(v_acc, [1]));

  const v_f118 = v_acc => v_f119(v_and(v_acc, [1]));

  const v_f117 = v_acc => v_f118(v_and(v_acc, [1]));

  const v_f116 = v_acc => v_f117(v_and(v_acc, [1]));

  const v_f115 = v_acc => v_f116(v_and(v_acc, [1]));

  const v_f114 = v_acc => v_f115(v_and(v_acc, [1]));

  const v_f113 = v_acc => v_f114(v_and(v_acc, [1]));

  const v_f112 = v_acc => v_f113(v_and(v_acc, [1]));

  const v_f111 = v_acc => v_f112(v_and(v_acc, [1]));

  const v_f110 = v_acc => v_f111(v_and(v_acc, [1]));

  const v_f109 = v_acc => v_f110(v_and(v_acc, [1]));

  const v_f108 = v_acc => v_f109(v_and(v_acc, [1]));

  const v_f107 = v_acc => v_f108(v_and(v_acc, [1]));

  const v_f106 = v_acc => v_f107(v_and(v_acc, [1]));

  const v_f105 = v_acc => v_f106(v_and(v_acc, [1]));

  const v_f104 = v_acc => v_f105(v_and(v_acc, [1]));

  const v_f103 = v_acc => v_f104(v_and(v_acc, [1]));

  const v_f102 = v_acc => v_f103(v_and(v_acc, [1]));

  const v_f101 = v_acc => v_f102(v_and(v_acc, [1]));

  const v_f100 = v_acc => v_f101(v_and(v_acc, [1]));

  const v_f99 = v_acc => v_f100(v_and(v_acc, [1]));

  const v_f98 = v_acc => v_f99(v_and(v_acc, [1]));

  const v_f97 = v_acc => v_f98(v_and(v_acc, [1]));

  const v_f96 = v_acc => v_f97(v_and(v_acc, [1]));

  const v_f95 = v_acc => v_f96(v_and(v_acc, [1]));

  const v_f94 = v_acc => v_f95(v_and(v_acc, [1]));

  const v_f93 = v_acc => v_f94(v_and(v_acc, [1]));

  const v_f92 = v_acc => v_f93(v_and(v_acc, [1]));

  const v_f91 = v_acc => v_f92(v_and(v_acc, [1]));

  const v_f90 = v_acc => v_f91(v_and(v_acc, [1]));

  const v_f89 = v_acc => v_f90(v_and(v_acc, [1]));

  const v_f88 = v_acc => v_f89(v_and(v_acc, [1]));

  const v_f87 = v_acc => v_f88(v_and(v_acc, [1]));

  const v_f86 = v_acc => v_f87(v_and(v_acc, [1]));

  const v_f85 = v_acc => v_f86(v_and(v_acc, [1]));

  const v_f84 = v_acc => v_f85(v_and(v_acc, [1]));

  const v_f83 = v_acc => v_f84(v_and(v_acc, [1]));

  const v_f82 = v_acc => v_f83(v_and(v_acc, [1]));

  const v_f81 = v_acc => v_f82(v_and(v_acc, [1]));

  const v_f80 = v_acc => v_f81(v_and(v_acc, [1]));

  const v_f79 = v_acc => v_f80(v_and(v_acc, [1]));

  const v_f78 = v_acc => v_f79(v_and(v_acc, [1]));

  const v_f77 = v_acc => v_f78(v_and(v_acc, [1]));

  const v_f76 = v_acc => v_f77(v_and(v_acc, [1]));

  const v_f75 = v_acc => v_f76(v_and(v_acc, [1]));

  const v_f74 = v_acc => v_f75(v_and(v_acc, [1]));

  const v_f73 = v_acc => v_f74(v_and(v_acc, [1]));

  const v_f72 = v_acc => v_f73(v_and(v_acc, [1]));

  const v_f71 = v_acc => v_f72(v_and(v_acc, [1]));

  const v_f70 = v_acc => v_f71(v_and(v_acc, [1]));

  const v_f69 = v_acc => v_f70(v_and(v_acc, [1]));

  const v_f68 = v_acc => v_f69(v_and(v_acc, [1]));

  const v_f67 = v_acc => v_f68(v_and(v_acc, [1]));

  const v_f66 = v_acc => v_f67(v_and(v_acc, [1]));

  const v_f65 = v_acc => v_f66(v_and(v_acc, [1]));

  const v_f64 = v_acc => v_f65(v_and(v_acc, [1]));

  const v_f63 = v_acc => v_f64(v_and(v_acc, [1]));

  const v_f62 = v_acc => v_f63(v_and(v_acc, [1]));

  const v_f61 = v_acc => v_f62(v_and(v_acc, [1]));

  const v_f60 = v_acc => v_f61(v_and(v_acc, [1]));

  const v_f59 = v_acc => v_f60(v_and(v_acc, [1]));

  const v_f58 = v_acc => v_f59(v_and(v_acc, [1]));

  const v_f57 = v_acc => v_f58(v_and(v_acc, [1]));

  const v_f56 = v_acc => v_f57(v_and(v_acc, [1]));

  const v_f55 = v_acc => v_f56(v_and(v_acc, [1]));

  const v_f54 = v_acc => v_f55(v_and(v_acc, [1]));

  const v_f53 = v_acc => v_f54(v_and(v_acc, [1]));

  const v_f52 = v_acc => v_f53(v_and(v_acc, [1]));

  const v_f51 = v_acc => v_f52(v_and(v_acc, [1]));

  const v_f50 = v_acc => v_f51(v_and(v_acc, [1]));

  const v_f49 = v_acc => v_f50(v_and(v_acc, [1]));

  const v_f48 = v_acc => v_f49(v_and(v_acc, [1]));

  const v_f47 = v_acc => v_f48(v_and(v_acc, [1]));

  const v_f46 = v_acc => v_f47(v_and(v_acc, [1]));

  const v_f45 = v_acc => v_f46(v_and(v_acc, [1]));

  const v_f44 = v_acc => v_f45(v_and(v_acc, [1]));

  const v_f43 = v_acc => v_f44(v_and(v_acc, [1]));

  const v_f42 = v_acc => v_f43(v_and(v_acc, [1]));

  const v_f41 = v_acc => v_f42(v_and(v_acc, [1]));

  const v_f40 = v_acc => v_f41(v_and(v_acc, [1]));

  const v_f39 = v_acc => v_f40(v_and(v_acc, [1]));

  const v_f38 = v_acc => v_f39(v_and(v_acc, [1]));

  const v_f37 = v_acc => v_f38(v_and(v_acc, [1]));

  const v_f36 = v_acc => v_f37(v_and(v_acc, [1]));

  const v_f35 = v_acc => v_f36(v_and(v_acc, [1]));

  const v_f34 = v_acc => v_f35(v_and(v_acc, [1]));

  const v_f33 = v_acc => v_f34(v_and(v_acc, [1]));

  const v_f32 = v_acc => v_f33(v_and(v_acc, [1]));

  const v_f31 = v_acc => v_f32(v_and(v_acc, [1]));

  const v_f30 = v_acc => v_f31(v_and(v_acc, [1]));

  const v_f29 = v_acc => v_f30(v_and(v_acc, [1]));

  const v_f28 = v_acc => v_f29(v_and(v_acc, [1]));

  const v_f27 = v_acc => v_f28(v_and(v_acc, [1]));

  const v_f26 = v_acc => v_f27(v_and(v_acc, [1]));

  const v_f25 = v_acc => v_f26(v_and(v_acc, [1]));

  const v_f24 = v_acc => v_f25(v_and(v_acc, [1]));

  const v_f23 = v_acc => v_f24(v_and(v_acc, [1]));

  const v_f22 = v_acc => v_f23(v_and(v_acc, [1]));

  const v_f21 = v_acc => v_f22(v_and(v_acc, [1]));

  const v_f20 = v_acc => v_f21(v_and(v_acc, [1]));

  const v_f19 = v_acc => v_f20(v_and(v_acc, [1]));

  const v_f18 = v_acc => v_f19(v_and(v_acc, [1]));

  const v_f17 = v_acc => v_f18(v_and(v_acc, [1]));

  const v_f16 = v_acc => v_f17(v_and(v_acc, [1]));

  const v_f15 = v_acc => v_f16(v_and(v_acc, [1]));

  const v_f14 = v_acc => v_f15(v_and(v_acc, [1]));

  const v_f13 = v_acc => v_f14(v_and(v_acc, [1]));

  const v_f12 = v_acc => v_f13(v_and(v_acc, [1]));

  const v_f11 = v_acc => v_f12(v_and(v_acc, [1]));

  const v_f10 = v_acc => v_f11(v_and(v_acc, [1]));

  const v_f9 = v_acc => v_f10(v_and(v_acc, [1]));

  const v_f8 = v_acc => v_f9(v_and(v_acc, [1]));

  const v_f7 = v_acc => v_f8(v_and(v_acc, [1]));

  const v_f6 = v_acc => v_f7(v_and(v_acc, [1]));

  const v_f5 = v_acc => v_f6(v_and(v_acc, [1]));

  const v_f4 = v_acc => v_f5(v_and(v_acc, [1]));

  const v_f3 = v_acc => v_f4(v_and(v_acc, [1]));

  const v_f2 = v_acc => v_f3(v_and(v_acc, [1]));

  const v_f1 = v_acc => v_f2(v_and(v_acc, [1]));

  const main = [7, v_showBool(v_f1([1])), [5, [0]]];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
