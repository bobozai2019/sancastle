Shader hash ad681d31-ede321ee-f362235a-4975fdb8

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture2d (float,float,float,float) t3
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyzw
      dcl_input_ps linear v4.xy
      dcl_output o0.xyzw
      dcl_temps 4
   0: lt r0.x, v1.y, l(0)
   1: discard_nz r0.x
   2: itof r0.xy, cb0[139].xyxx
   3: div r0.zw, v1.xxxz, cb0[116].xxxz
   4: add_sat r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
   5: mad r0.xy, r0.zwzz, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   6: sample_l(texture2d)(float,float,float,float) r1.xyz, r0.zwzz, t2.xyzw, s1, l(0)
   7: add r1.xyz, r1.xyzx, -cb0[40].xyzx
   8: round_ni r0.zw, r0.xxxy
   9: frc r0.xy, r0.xyxx
  10: ftoi r0.zw, r0.zzzw
  11: iadd r2.xy, r0.zwzz, l(1, 1, 0, 0)
  12: imax r2.xy, r2.xyxx, l(0, 0, 0, 0)
  13: iadd r2.zw, cb0[139].xxxy, l(0, 0, -1, -1)
  14: imin r2.xy, r2.zwzz, r2.xyxx
  15: imad r1.w, r2.y, cb0[139].x, r2.x
  16: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.w, l(4), t1.xyxx
  17: ushr r1.w, r2.x, l(12)
  18: bfi r1.w, l(12), l(20), r2.y, r1.w
  19: and r1.w, r1.w, l(0x003fffff)
  20: utof r1.w, r1.w
  21: iadd r3.xyzw, r0.zwzw, l(1, 0, 0, 1)
  22: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  23: imin r0.zw, r2.zzzw, r0.zzzw
  24: imad r0.z, r0.w, cb0[139].x, r0.z
  25: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(4), t1.xxxy
  26: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  27: imin r2.xyzw, r2.zwzw, r3.xyzw
  28: imad r2.xy, r2.ywyy, cb0[139].xxxx, r2.xzxx
  29: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.yz, r2.y, l(4), t1.xxyx
  30: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xw, r2.x, l(4), t1.xxxy
  31: ushr r2.xy, r2.xyxx, l(12, 12, 0, 0)
  32: bfi r2.xy, l(12, 12, 0, 0), l(20, 20, 0, 0), r2.wzww, r2.xyxx
  33: and r2.xy, r2.xyxx, l(0x003fffff, 0x003fffff, 0, 0)
  34: utof r2.xy, r2.xyxx
  35: mul r2.y, r2.y, l(0.000001)
  36: mad r1.w, r1.w, l(0.000001), -r2.y
  37: mad r1.w, r0.x, r1.w, r2.y
  38: ushr r0.z, r0.z, l(12)
  39: bfi r0.z, l(12), l(20), r0.w, r0.z
  40: and r0.z, r0.z, l(0x003fffff)
  41: utof r0.z, r0.z
  42: mul r0.z, r0.z, l(0.000001)
  43: mad r0.w, r2.x, l(0.000001), -r0.z
  44: mad r0.x, r0.x, r0.w, r0.z
  45: add r0.z, -r0.x, r1.w
  46: mad r0.x, r0.y, r0.z, r0.x
  47: mul r0.x, r0.x, l(-0.721348)
  48: exp r0.x, r0.x
  49: mul r0.yzw, v1.yyyy, cb0[135].xxyz
  50: mad r0.yzw, cb0[134].xxyz, v1.xxxx, r0.yyzw
  51: mad r0.yzw, cb0[136].xxyz, v1.zzzz, r0.yyzw
  52: add r0.yzw, r0.yyzw, cb0[137].xxyz
  53: ge r1.w, l(0), r0.w
  54: ge r2.x, r0.w, l(1.000000)
  55: sample_c_lz(texture2d)(float,float,float,float) r0.y, r0.yzyy, t0.xxxx, s0, r0.w
  56: or r0.z, r1.w, r2.x
  57: movc r0.y, r0.z, l(1.000000), r0.y
  58: mul r0.x, r0.x, r0.y
  59: dp3 r0.y, v2.xyzx, -cb0[123].xyzx
  60: max r0.y, r0.y, l(0)
  61: mul r0.yzw, r0.yyyy, cb0[125].xxyz
  62: dp3 r1.w, v2.xyzx, -cb0[124].xyzx
  63: max r1.w, r1.w, l(0)
  64: mul r2.xyz, r1.wwww, cb0[126].xyzx
  65: mad r0.xyz, r0.yzwy, r0.xxxx, r2.xyzx
  66: sample_indexable(texture2d)(float,float,float,float) r0.w, v4.xyxx, t3.yzwx, s2
  67: add r0.w, r0.w, r0.w
  68: mul r2.xyz, v3.xyzx, cb1[0].xyzx
  69: mad r3.xyz, r2.xyzx, r0.wwww, -r2.xyzx
  70: mad_sat r2.xyz, v3.wwww, r3.xyzx, r2.xyzx
  71: mad r0.xyz, r2.xyzx, r0.xyzx, cb1[1].xyzx
  72: mul r3.xyzw, cb0[116].xxzz, l(0.500000, -0.500000, 0.500000, -0.500000)
  73: lt r3.xz, v1.xxzx, r3.xxzx
  74: lt r3.yw, r3.yyyw, v1.xxxz
  75: and r0.w, r3.y, r3.x
  76: and r0.w, r3.z, r0.w
  77: and r0.w, r3.w, r0.w
  78: and r0.w, r0.w, l(1.000000)
  79: mad r1.xyz, r0.wwww, r1.xyzx, cb0[40].xyzx
  80: mad o0.xyz, r1.xyzx, r2.xyzx, r0.xyzx
  81: mov o0.w, v1.y
  82: ret
