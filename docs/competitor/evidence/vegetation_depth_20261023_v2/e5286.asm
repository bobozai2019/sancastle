Shader hash 77d3c73b-dcf96d91-02bb9f65-9b7ac97b

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[142], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_structured t0, 16
      dcl_resource_structured t1, 16
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xy
      dcl_output o0.xyzw
      dcl_temps 4
   0: itof r0.xy, cb0[139].xyxx
   1: mad r0.xy, v3.xyxx, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   2: round_ni r0.zw, r0.xxxy
   3: frc r0.xy, r0.xyxx
   4: ftoi r0.zw, r0.zzzw
   5: iadd r1.xy, r0.zwzz, l(1, 1, 0, 0)
   6: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
   7: iadd r1.zw, cb0[139].xxxy, l(0, 0, -1, -1)
   8: imin r1.xy, r1.zwzz, r1.xyxx
   9: imad r1.x, r1.y, cb0[139].x, r1.x
  10: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(8), t0.xyxx
  11: ushr r1.x, r1.x, l(12)
  12: bfi r1.x, l(12), l(20), r1.y, r1.x
  13: and r1.x, r1.x, l(0.000000)
  14: iadd r2.xyzw, r0.zwzw, l(1, 0, 0, 1)
  15: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  16: imin r0.zw, r1.zzzw, r0.zzzw
  17: imad r0.z, r0.w, cb0[139].x, r0.z
  18: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(8), t0.xxxy
  19: imax r2.xyzw, r2.xyzw, l(0, 0, 0, 0)
  20: imin r2.xyzw, r1.zwzw, r2.xyzw
  21: imad r1.yz, r2.yywy, cb0[139].xxxx, r2.xxzx
  22: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(8), t0.xxxy
  23: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.y, l(8), t0.xyxx
  24: ushr r1.y, r1.z, l(12)
  25: bfi r1.y, l(12), l(20), r1.w, r1.y
  26: and r1.y, r1.y, l(0.000000)
  27: utof r1.xy, r1.xyxx
  28: mul r1.y, r1.y, l(0.000001)
  29: mad r1.x, r1.x, l(0.000001), -r1.y
  30: mad r1.x, r0.x, r1.x, r1.y
  31: ushr r1.y, r2.x, l(12)
  32: bfi r1.y, l(12), l(20), r2.y, r1.y
  33: and r1.y, r1.y, l(0.000000)
  34: utof r1.y, r1.y
  35: ushr r0.z, r0.z, l(12)
  36: bfi r0.z, l(12), l(20), r0.w, r0.z
  37: and r0.z, r0.z, l(0.000000)
  38: utof r0.z, r0.z
  39: mul r0.z, r0.z, l(0.000001)
  40: mad r0.w, r1.y, l(0.000001), -r0.z
  41: mad r0.x, r0.x, r0.w, r0.z
  42: add r0.z, -r0.x, r1.x
  43: mad r0.x, r0.y, r0.z, r0.x
  44: lt r0.y, r0.x, v1.y
  45: add r0.x, -r0.x, v1.y
  46: discard_nz r0.y
  47: div r0.yz, v1.xxzx, cb0[116].xxzx
  48: add_sat r0.yz, r0.yyzy, l(0.000000, 0.500000, 0.500000, 0.000000)
  49: itof r1.xy, cb0[141].xyxx
  50: mad r0.yz, r0.yyzy, r1.xxyx, l(0.000000, -0.500000, -0.500000, 0.000000)
  51: round_ni r1.xy, r0.yzyy
  52: frc r0.yz, r0.yyzy
  53: ftoi r1.xy, r1.xyxx
  54: iadd r1.zw, r1.xxxy, l(0, 0, 1, 1)
  55: imax r1.zw, r1.zzzw, l(0, 0, 0, 0)
  56: iadd r2.xy, cb0[141].xyxx, l(-1, -1, 0, 0)
  57: imin r1.zw, r1.zzzw, r2.xxxy
  58: imad r0.w, r1.w, cb0[141].x, r1.z
  59: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r0.w, l(4), t1.xxxy
  60: ushr r0.w, r1.z, l(12)
  61: bfi r0.w, l(12), l(20), r1.w, r0.w
  62: and r0.w, r0.w, l(0x003fffff)
  63: utof r0.w, r0.w
  64: iadd r3.xyzw, r1.xyxy, l(1, 0, 0, 1)
  65: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
  66: imin r1.xy, r2.xyxx, r1.xyxx
  67: imad r1.x, r1.y, cb0[141].x, r1.x
  68: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(4), t1.xyxx
  69: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  70: imin r2.xyzw, r2.xyxy, r3.xyzw
  71: imad r1.zw, r2.yyyw, cb0[141].xxxx, r2.xxxz
  72: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.w, l(4), t1.xyxx
  73: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(4), t1.xxxy
  74: ushr r2.x, r2.x, l(12)
  75: bfi r2.x, l(12), l(20), r2.y, r2.x
  76: and r2.x, r2.x, l(0x003fffff)
  77: utof r2.x, r2.x
  78: mul r2.x, r2.x, l(0.000001)
  79: mad r0.w, r0.w, l(0.000001), -r2.x
  80: mad r0.w, r0.y, r0.w, r2.x
  81: ushr r1.xz, r1.xxzx, l(12, 0, 12, 0)
  82: bfi r1.xz, l(12, 0, 12, 0), l(20, 0, 20, 0), r1.yywy, r1.xxzx
  83: and r1.xz, r1.xxzx, l(0x003fffff, 0, 0x003fffff, 0)
  84: utof r1.xz, r1.xxzx
  85: mul r1.x, r1.x, l(0.000001)
  86: mad r1.y, r1.z, l(0.000001), -r1.x
  87: mad r0.y, r0.y, r1.y, r1.x
  88: add r0.w, -r0.y, r0.w
  89: mad r0.y, r0.z, r0.w, r0.y
  90: mul r0.y, r0.y, l(-0.721348)
  91: exp r0.y, r0.y
  92: dp3 r0.z, v2.xyzx, -cb0[123].xyzx
  93: max r0.z, r0.z, l(0)
  94: mul r1.xyz, r0.zzzz, cb0[125].xyzx
  95: dp3 r0.z, v2.xyzx, -cb0[124].xyzx
  96: max r0.z, r0.z, l(0)
  97: mul r2.xyz, r0.zzzz, cb0[126].xyzx
  98: mad r0.yzw, r1.xxyz, r0.yyyy, r2.xxyz
  99: utof r1.x, cb0[113].x
 100: add r0.x, r0.x, r1.x
 101: mul r1.y, r0.x, l(0.500000)
 102: dp2 r1.x, v1.xzxx, l(0.020000, 0.020000, 0.000000, 0.000000)
 103: sample_indexable(texture2d)(float,float,float,float) r0.x, r1.xyxx, t2.xyzw, s0
 104: add r1.xyz, -cb0[127].xyzx, cb0[128].xyzx
 105: mad_sat r1.xyz, r0.xxxx, r1.xyzx, cb0[127].xyzx
 106: mul r2.xyz, r1.xyzx, cb0[40].xyzx
 107: mad o0.xyz, r1.xyzx, r0.yzwy, r2.xyzx
 108: mov o0.w, l(1.000000)
 109: ret
