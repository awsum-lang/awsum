"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __parseInt32 = s => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
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

  const main = (v__inl3_r =>
    (() => {
      let v__inl40_scrut;
      $join39: {
        const __s = (s => {
          switch (s[0]) {
            case 3: {
              return [4, "err"];
            }
            case 4: {
              return __concat("ok:", String(v__inl3_r[1]));
            }
          }
        })(v__inl3_r);
        switch (__s[0]) {
          case 3: {
            return [7, "STRING_TOO_LONG", [5, [0]]];
          }
          case 4: {
            const v_a = __s[1];
            v__inl40_scrut = (v__inl6_r =>
              (s => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_31 = s[1];
                    return [3, v__do_e_31];
                  }
                  case 4: {
                    const v_b = s[1];
                    const v__inl9_r = __parseInt32("0");
                    {
                      const __s = (s => {
                        switch (s[0]) {
                          case 3: {
                            return [4, "err"];
                          }
                          case 4: {
                            return __concat("ok:", String(v__inl9_r[1]));
                          }
                        }
                      })(v__inl9_r);
                      switch (__s[0]) {
                        case 3: {
                          const v__do_e_30 = __s[1];
                          return [3, v__do_e_30];
                        }
                        case 4: {
                          const v_c = __s[1];
                          const v__inl12_r = __parseInt32("2147483647");
                          {
                            const __s = (s => {
                              switch (s[0]) {
                                case 3: {
                                  return [4, "err"];
                                }
                                case 4: {
                                  return __concat("ok:", String(v__inl12_r[1]));
                                }
                              }
                            })(v__inl12_r);
                            switch (__s[0]) {
                              case 3: {
                                const v__do_e_29 = __s[1];
                                return [3, v__do_e_29];
                              }
                              case 4: {
                                const v_d = __s[1];
                                const v__inl15_r = __parseInt32("-2147483648");
                                {
                                  const __s = (s => {
                                    switch (s[0]) {
                                      case 3: {
                                        return [4, "err"];
                                      }
                                      case 4: {
                                        return __concat(
                                          "ok:",
                                          String(v__inl15_r[1])
                                        );
                                      }
                                    }
                                  })(v__inl15_r);
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__do_e_28 = __s[1];
                                      return [3, v__do_e_28];
                                    }
                                    case 4: {
                                      const v_e = __s[1];
                                      const v__inl18_r = __parseInt32(
                                        "2147483648"
                                      );
                                      {
                                        const __s = (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              return [4, "err"];
                                            }
                                            case 4: {
                                              return __concat(
                                                "ok:",
                                                String(v__inl18_r[1])
                                              );
                                            }
                                          }
                                        })(v__inl18_r);
                                        switch (__s[0]) {
                                          case 3: {
                                            const v__do_e_27 = __s[1];
                                            return [3, v__do_e_27];
                                          }
                                          case 4: {
                                            const v_f = __s[1];
                                            const v__inl21_r = __parseInt32(
                                              "-2147483649"
                                            );
                                            {
                                              const __s = (s => {
                                                switch (s[0]) {
                                                  case 3: {
                                                    return [4, "err"];
                                                  }
                                                  case 4: {
                                                    return __concat(
                                                      "ok:",
                                                      String(v__inl21_r[1])
                                                    );
                                                  }
                                                }
                                              })(v__inl21_r);
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__do_e_26 = __s[1];
                                                  return [3, v__do_e_26];
                                                }
                                                case 4: {
                                                  const v_g = __s[1];
                                                  const v__inl24_r = __parseInt32(
                                                    ""
                                                  );
                                                  {
                                                    const __s = (s => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          return [4, "err"];
                                                        }
                                                        case 4: {
                                                          return __concat(
                                                            "ok:",
                                                            String(
                                                              v__inl24_r[1]
                                                            )
                                                          );
                                                        }
                                                      }
                                                    })(v__inl24_r);
                                                    switch (__s[0]) {
                                                      case 3: {
                                                        const v__do_e_25 = __s[1];
                                                        return [3, v__do_e_25];
                                                      }
                                                      case 4: {
                                                        const v_h = __s[1];
                                                        const v__inl27_r = __parseInt32(
                                                          "-"
                                                        );
                                                        {
                                                          const __s = (s => {
                                                            switch (s[0]) {
                                                              case 3: {
                                                                return [
                                                                  4,
                                                                  "err"
                                                                ];
                                                              }
                                                              case 4: {
                                                                return __concat(
                                                                  "ok:",
                                                                  String(
                                                                    v__inl27_r[1]
                                                                  )
                                                                );
                                                              }
                                                            }
                                                          })(v__inl27_r);
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v__do_e_24 = __s[1];
                                                              return [
                                                                3,
                                                                v__do_e_24
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_i = __s[1];
                                                              const v__inl30_r = __parseInt32(
                                                                "+42"
                                                              );
                                                              {
                                                                const __s = (s => {
                                                                  switch (s[0]) {
                                                                    case 3: {
                                                                      return [
                                                                        4,
                                                                        "err"
                                                                      ];
                                                                    }
                                                                    case 4: {
                                                                      return __concat(
                                                                        "ok:",
                                                                        String(
                                                                          v__inl30_r[1]
                                                                        )
                                                                      );
                                                                    }
                                                                  }
                                                                })(v__inl30_r);
                                                                switch (__s[0]) {
                                                                  case 3: {
                                                                    const v__do_e_23 = __s[1];
                                                                    return [
                                                                      3,
                                                                      v__do_e_23
                                                                    ];
                                                                  }
                                                                  case 4: {
                                                                    const v_j = __s[1];
                                                                    const v__inl33_r = __parseInt32(
                                                                      " 42"
                                                                    );
                                                                    {
                                                                      const __s = (s => {
                                                                        switch (s[0]) {
                                                                          case 3: {
                                                                            return [
                                                                              4,
                                                                              "err"
                                                                            ];
                                                                          }
                                                                          case 4: {
                                                                            return __concat(
                                                                              "ok:",
                                                                              String(
                                                                                v__inl33_r[1]
                                                                              )
                                                                            );
                                                                          }
                                                                        }
                                                                      })(
                                                                        v__inl33_r
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v__do_e_22 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v__do_e_22
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_k = __s[1];
                                                                          const v__inl36_r = __parseInt32(
                                                                            "12abc"
                                                                          );
                                                                          {
                                                                            const __s = (s => {
                                                                              switch (s[0]) {
                                                                                case 3: {
                                                                                  return [
                                                                                    4,
                                                                                    "err"
                                                                                  ];
                                                                                }
                                                                                case 4: {
                                                                                  return __concat(
                                                                                    "ok:",
                                                                                    String(
                                                                                      v__inl36_r[1]
                                                                                    )
                                                                                  );
                                                                                }
                                                                              }
                                                                            })(
                                                                              v__inl36_r
                                                                            );
                                                                            switch (__s[0]) {
                                                                              case 3: {
                                                                                const v__do_e_21 = __s[1];
                                                                                return [
                                                                                  3,
                                                                                  v__do_e_21
                                                                                ];
                                                                              }
                                                                              case 4: {
                                                                                const v_l = __s[1];
                                                                                {
                                                                                  const __s = __concat(
                                                                                    v_a,
                                                                                    ", "
                                                                                  );
                                                                                  switch (__s[0]) {
                                                                                    case 3: {
                                                                                      const v__do_e_20 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v__do_e_20
                                                                                      ];
                                                                                    }
                                                                                    case 4: {
                                                                                      const v_s0 = __s[1];
                                                                                      {
                                                                                        const __s = __concat(
                                                                                          v_s0,
                                                                                          v_b
                                                                                        );
                                                                                        switch (__s[0]) {
                                                                                          case 3: {
                                                                                            const v__do_e_19 = __s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v__do_e_19
                                                                                            ];
                                                                                          }
                                                                                          case 4: {
                                                                                            const v_s1 = __s[1];
                                                                                            {
                                                                                              const __s = __concat(
                                                                                                v_s1,
                                                                                                ", "
                                                                                              );
                                                                                              switch (__s[0]) {
                                                                                                case 3: {
                                                                                                  const v__do_e_18 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v__do_e_18
                                                                                                  ];
                                                                                                }
                                                                                                case 4: {
                                                                                                  const v_s2 = __s[1];
                                                                                                  {
                                                                                                    const __s = __concat(
                                                                                                      v_s2,
                                                                                                      v_c
                                                                                                    );
                                                                                                    switch (__s[0]) {
                                                                                                      case 3: {
                                                                                                        const v__do_e_17 = __s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v__do_e_17
                                                                                                        ];
                                                                                                      }
                                                                                                      case 4: {
                                                                                                        const v_s3 = __s[1];
                                                                                                        {
                                                                                                          const __s = __concat(
                                                                                                            v_s3,
                                                                                                            ", "
                                                                                                          );
                                                                                                          switch (__s[0]) {
                                                                                                            case 3: {
                                                                                                              const v__do_e_16 = __s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v__do_e_16
                                                                                                              ];
                                                                                                            }
                                                                                                            case 4: {
                                                                                                              const v_s4 = __s[1];
                                                                                                              {
                                                                                                                const __s = __concat(
                                                                                                                  v_s4,
                                                                                                                  v_d
                                                                                                                );
                                                                                                                switch (__s[0]) {
                                                                                                                  case 3: {
                                                                                                                    const v__do_e_15 = __s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v__do_e_15
                                                                                                                    ];
                                                                                                                  }
                                                                                                                  case 4: {
                                                                                                                    const v_s5 = __s[1];
                                                                                                                    {
                                                                                                                      const __s = __concat(
                                                                                                                        v_s5,
                                                                                                                        ", "
                                                                                                                      );
                                                                                                                      switch (__s[0]) {
                                                                                                                        case 3: {
                                                                                                                          const v__do_e_14 = __s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v__do_e_14
                                                                                                                          ];
                                                                                                                        }
                                                                                                                        case 4: {
                                                                                                                          const v_s6 = __s[1];
                                                                                                                          {
                                                                                                                            const __s = __concat(
                                                                                                                              v_s6,
                                                                                                                              v_e
                                                                                                                            );
                                                                                                                            switch (__s[0]) {
                                                                                                                              case 3: {
                                                                                                                                const v__do_e_13 = __s[1];
                                                                                                                                return [
                                                                                                                                  3,
                                                                                                                                  v__do_e_13
                                                                                                                                ];
                                                                                                                              }
                                                                                                                              case 4: {
                                                                                                                                const v_s7 = __s[1];
                                                                                                                                {
                                                                                                                                  const __s = __concat(
                                                                                                                                    v_s7,
                                                                                                                                    ", "
                                                                                                                                  );
                                                                                                                                  switch (__s[0]) {
                                                                                                                                    case 3: {
                                                                                                                                      const v__do_e_12 = __s[1];
                                                                                                                                      return [
                                                                                                                                        3,
                                                                                                                                        v__do_e_12
                                                                                                                                      ];
                                                                                                                                    }
                                                                                                                                    case 4: {
                                                                                                                                      const v_s8 = __s[1];
                                                                                                                                      {
                                                                                                                                        const __s = __concat(
                                                                                                                                          v_s8,
                                                                                                                                          v_f
                                                                                                                                        );
                                                                                                                                        switch (__s[0]) {
                                                                                                                                          case 3: {
                                                                                                                                            const v__do_e_11 = __s[1];
                                                                                                                                            return [
                                                                                                                                              3,
                                                                                                                                              v__do_e_11
                                                                                                                                            ];
                                                                                                                                          }
                                                                                                                                          case 4: {
                                                                                                                                            const v_s9 = __s[1];
                                                                                                                                            {
                                                                                                                                              const __s = __concat(
                                                                                                                                                v_s9,
                                                                                                                                                ", "
                                                                                                                                              );
                                                                                                                                              switch (__s[0]) {
                                                                                                                                                case 3: {
                                                                                                                                                  const v__do_e_10 = __s[1];
                                                                                                                                                  return [
                                                                                                                                                    3,
                                                                                                                                                    v__do_e_10
                                                                                                                                                  ];
                                                                                                                                                }
                                                                                                                                                case 4: {
                                                                                                                                                  const v_s10 = __s[1];
                                                                                                                                                  {
                                                                                                                                                    const __s = __concat(
                                                                                                                                                      v_s10,
                                                                                                                                                      v_g
                                                                                                                                                    );
                                                                                                                                                    switch (__s[0]) {
                                                                                                                                                      case 3: {
                                                                                                                                                        const v__do_e_9 = __s[1];
                                                                                                                                                        return [
                                                                                                                                                          3,
                                                                                                                                                          v__do_e_9
                                                                                                                                                        ];
                                                                                                                                                      }
                                                                                                                                                      case 4: {
                                                                                                                                                        const v_s11 = __s[1];
                                                                                                                                                        {
                                                                                                                                                          const __s = __concat(
                                                                                                                                                            v_s11,
                                                                                                                                                            ", "
                                                                                                                                                          );
                                                                                                                                                          switch (__s[0]) {
                                                                                                                                                            case 3: {
                                                                                                                                                              const v__do_e_8 = __s[1];
                                                                                                                                                              return [
                                                                                                                                                                3,
                                                                                                                                                                v__do_e_8
                                                                                                                                                              ];
                                                                                                                                                            }
                                                                                                                                                            case 4: {
                                                                                                                                                              const v_s12 = __s[1];
                                                                                                                                                              {
                                                                                                                                                                const __s = __concat(
                                                                                                                                                                  v_s12,
                                                                                                                                                                  v_h
                                                                                                                                                                );
                                                                                                                                                                switch (__s[0]) {
                                                                                                                                                                  case 3: {
                                                                                                                                                                    const v__do_e_7 = __s[1];
                                                                                                                                                                    return [
                                                                                                                                                                      3,
                                                                                                                                                                      v__do_e_7
                                                                                                                                                                    ];
                                                                                                                                                                  }
                                                                                                                                                                  case 4: {
                                                                                                                                                                    const v_s13 = __s[1];
                                                                                                                                                                    {
                                                                                                                                                                      const __s = __concat(
                                                                                                                                                                        v_s13,
                                                                                                                                                                        ", "
                                                                                                                                                                      );
                                                                                                                                                                      switch (__s[0]) {
                                                                                                                                                                        case 3: {
                                                                                                                                                                          const v__do_e_6 = __s[1];
                                                                                                                                                                          return [
                                                                                                                                                                            3,
                                                                                                                                                                            v__do_e_6
                                                                                                                                                                          ];
                                                                                                                                                                        }
                                                                                                                                                                        case 4: {
                                                                                                                                                                          const v_s14 = __s[1];
                                                                                                                                                                          {
                                                                                                                                                                            const __s = __concat(
                                                                                                                                                                              v_s14,
                                                                                                                                                                              v_i
                                                                                                                                                                            );
                                                                                                                                                                            switch (__s[0]) {
                                                                                                                                                                              case 3: {
                                                                                                                                                                                const v__do_e_5 = __s[1];
                                                                                                                                                                                return [
                                                                                                                                                                                  3,
                                                                                                                                                                                  v__do_e_5
                                                                                                                                                                                ];
                                                                                                                                                                              }
                                                                                                                                                                              case 4: {
                                                                                                                                                                                const v_s15 = __s[1];
                                                                                                                                                                                {
                                                                                                                                                                                  const __s = __concat(
                                                                                                                                                                                    v_s15,
                                                                                                                                                                                    ", "
                                                                                                                                                                                  );
                                                                                                                                                                                  switch (__s[0]) {
                                                                                                                                                                                    case 3: {
                                                                                                                                                                                      const v__do_e_4 = __s[1];
                                                                                                                                                                                      return [
                                                                                                                                                                                        3,
                                                                                                                                                                                        v__do_e_4
                                                                                                                                                                                      ];
                                                                                                                                                                                    }
                                                                                                                                                                                    case 4: {
                                                                                                                                                                                      const v_s16 = __s[1];
                                                                                                                                                                                      {
                                                                                                                                                                                        const __s = __concat(
                                                                                                                                                                                          v_s16,
                                                                                                                                                                                          v_j
                                                                                                                                                                                        );
                                                                                                                                                                                        switch (__s[0]) {
                                                                                                                                                                                          case 3: {
                                                                                                                                                                                            const v__do_e_3 = __s[1];
                                                                                                                                                                                            return [
                                                                                                                                                                                              3,
                                                                                                                                                                                              v__do_e_3
                                                                                                                                                                                            ];
                                                                                                                                                                                          }
                                                                                                                                                                                          case 4: {
                                                                                                                                                                                            const v_s17 = __s[1];
                                                                                                                                                                                            {
                                                                                                                                                                                              const __s = __concat(
                                                                                                                                                                                                v_s17,
                                                                                                                                                                                                ", "
                                                                                                                                                                                              );
                                                                                                                                                                                              switch (__s[0]) {
                                                                                                                                                                                                case 3: {
                                                                                                                                                                                                  const v__do_e_2 = __s[1];
                                                                                                                                                                                                  return [
                                                                                                                                                                                                    3,
                                                                                                                                                                                                    v__do_e_2
                                                                                                                                                                                                  ];
                                                                                                                                                                                                }
                                                                                                                                                                                                case 4: {
                                                                                                                                                                                                  const v_s18 = __s[1];
                                                                                                                                                                                                  {
                                                                                                                                                                                                    const __s = __concat(
                                                                                                                                                                                                      v_s18,
                                                                                                                                                                                                      v_k
                                                                                                                                                                                                    );
                                                                                                                                                                                                    switch (__s[0]) {
                                                                                                                                                                                                      case 3: {
                                                                                                                                                                                                        const v__do_e_1 = __s[1];
                                                                                                                                                                                                        return [
                                                                                                                                                                                                          3,
                                                                                                                                                                                                          v__do_e_1
                                                                                                                                                                                                        ];
                                                                                                                                                                                                      }
                                                                                                                                                                                                      case 4: {
                                                                                                                                                                                                        const v_s19 = __s[1];
                                                                                                                                                                                                        {
                                                                                                                                                                                                          const __s = __concat(
                                                                                                                                                                                                            v_s19,
                                                                                                                                                                                                            ", "
                                                                                                                                                                                                          );
                                                                                                                                                                                                          switch (__s[0]) {
                                                                                                                                                                                                            case 3: {
                                                                                                                                                                                                              const v__do_e_0 = __s[1];
                                                                                                                                                                                                              return [
                                                                                                                                                                                                                3,
                                                                                                                                                                                                                v__do_e_0
                                                                                                                                                                                                              ];
                                                                                                                                                                                                            }
                                                                                                                                                                                                            case 4: {
                                                                                                                                                                                                              const v_s20 = __s[1];
                                                                                                                                                                                                              return __concat(
                                                                                                                                                                                                                v_s20,
                                                                                                                                                                                                                v_l
                                                                                                                                                                                                              );
                                                                                                                                                                                                            }
                                                                                                                                                                                                          }
                                                                                                                                                                                                        }
                                                                                                                                                                                                      }
                                                                                                                                                                                                    }
                                                                                                                                                                                                  }
                                                                                                                                                                                                }
                                                                                                                                                                                              }
                                                                                                                                                                                            }
                                                                                                                                                                                          }
                                                                                                                                                                                        }
                                                                                                                                                                                      }
                                                                                                                                                                                    }
                                                                                                                                                                                  }
                                                                                                                                                                                }
                                                                                                                                                                              }
                                                                                                                                                                            }
                                                                                                                                                                          }
                                                                                                                                                                        }
                                                                                                                                                                      }
                                                                                                                                                                    }
                                                                                                                                                                  }
                                                                                                                                                                }
                                                                                                                                                              }
                                                                                                                                                            }
                                                                                                                                                          }
                                                                                                                                                        }
                                                                                                                                                      }
                                                                                                                                                    }
                                                                                                                                                  }
                                                                                                                                                }
                                                                                                                                              }
                                                                                                                                            }
                                                                                                                                          }
                                                                                                                                        }
                                                                                                                                      }
                                                                                                                                    }
                                                                                                                                  }
                                                                                                                                }
                                                                                                                              }
                                                                                                                            }
                                                                                                                          }
                                                                                                                        }
                                                                                                                      }
                                                                                                                    }
                                                                                                                  }
                                                                                                                }
                                                                                                              }
                                                                                                            }
                                                                                                          }
                                                                                                        }
                                                                                                      }
                                                                                                    }
                                                                                                  }
                                                                                                }
                                                                                              }
                                                                                            }
                                                                                          }
                                                                                        }
                                                                                      }
                                                                                    }
                                                                                  }
                                                                                }
                                                                              }
                                                                            }
                                                                          }
                                                                        }
                                                                      }
                                                                    }
                                                                  }
                                                                }
                                                              }
                                                            }
                                                          }
                                                        }
                                                      }
                                                    }
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              })(
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "err"];
                    }
                    case 4: {
                      return __concat("ok:", String(v__inl6_r[1]));
                    }
                  }
                })(v__inl6_r)
              ))(__parseInt32("-42"));
            break $join39;
          }
        }
      }
      switch (v__inl40_scrut[0]) {
        case 3: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
        case 4: {
          return [7, v__inl40_scrut[1], [5, [0]]];
        }
      }
    })())(__parseInt32("42"));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
