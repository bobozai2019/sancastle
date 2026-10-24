Shader hash 1d39f45d-c16454e1-bf79a91b-46389fb9

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[144], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_sampler s3, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture2d (float,float,float,float) t3
      dcl_resource_texture3d (float,float,float,float) t4
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v4.xyzw
      dcl_input_ps linear v5.xyw
      dcl_output o0.xyzw
      dcl_temps 5
   0: mul r0.xy, v1.xzxx, l(0.300000, 0.300000, 0.000000, 0.000000)
   1: sample_indexable(texture2d)(float,float,float,float) r0.xy, r0.xyxx, t3.xyzw, s2
   2: mad r0.z, cb0[113].y, l(0.500000), r0.y
   3: add r0.w, r0.z, l(0.500000)
   4: ge r1.x, r0.w, -r0.w
   5: movc r1.x, r1.x, l(1.000000), l(-1.000000)
   6: mul r0.w, r0.w, r1.x
   7: frc r0.w, r0.w
   8: dp2 r0.w, r1.xxxx, r0.wwww
   9: add r0.w, r0.w, l(-1.000000)
  10: mul r1.xy, r0.wwww, v5.xyxx
  11: mul r2.xyzw, v4.wxyw, l(5.000000, 0.100000, 0.100000, -1.731234)
  12: mad r1.zw, v1.xxxz, l(0.000000, 0.000000, 0.250000, 0.250000), r2.yyyz
  13: mad r1.xy, -r1.xyxx, l(0.100000, 0.100000, 0.000000, 0.000000), r1.zwzz
  14: add r3.xy, r1.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  15: add r0.y, r0.y, cb0[113].y
  16: add r0.x, r0.x, r0.x
  17: add r0.yw, r0.yyyy, l(0.000000, 0.500000, 0.000000, -0.500000)
  18: mul r3.zw, r0.wwwy, l(0.000000, 0.000000, 0.200000, 0.200000)
  19: sample_indexable(texture3d)(float,float,float,float) r0.y, r3.xyzx, t4.yxzw, s3
  20: ge r0.w, r0.z, -r0.z
  21: movc r0.w, r0.w, l(1.000000), l(-1.000000)
  22: mul r0.z, r0.w, r0.z
  23: frc r0.z, r0.z
  24: mul r1.x, r0.z, r0.w
  25: mad r0.z, r0.w, r0.z, l(-0.500000)
  26: add r0.z, abs(r0.z), abs(r0.z)
  27: mad r0.w, r1.x, l(2.000000), l(-1.000000)
  28: mul r1.xy, r0.wwww, v5.xyxx
  29: mad r1.xy, -r1.xyxx, l(0.100000, 0.100000, 0.000000, 0.000000), r1.zwzz
  30: add r3.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  31: sample_indexable(texture3d)(float,float,float,float) r0.w, r3.xywx, t4.yzwx, s3
  32: add r0.y, -r0.w, r0.y
  33: mad r0.y, r0.z, r0.y, r0.w
  34: exp r0.z, r2.w
  35: mov_sat r2.x, r2.x
  36: dp3 r0.w, cb0[125].xyzx, cb0[125].xyzx
  37: sqrt r0.w, r0.w
  38: mul r0.z, r0.w, r0.z
  39: mul r0.y, r0.z, r0.y
  40: mov_sat r0.zw, v4.wwwz
  41: add r0.w, r0.w, l(-0.001000)
  42: mul r0.z, r0.z, l(100.000000)
  43: min r0.z, r0.z, l(1.000000)
  44: mul_sat r0.w, r0.w, l(52.631580)
  45: mad r1.x, r0.w, l(-2.000000), l(3.000000)
  46: mul r0.w, r0.w, r0.w
  47: mul r0.w, r0.w, r1.x
  48: add r1.xyz, -cb0[127].xyzx, cb0[129].xyzx
  49: mad r1.xyz, r0.wwww, r1.xyzx, cb0[127].xyzx
  50: add r2.yzw, -r1.xxyz, cb0[130].xxyz
  51: mul_sat r0.w, v5.w, l(20.000000)
  52: mad r1.xyz, r0.wwww, r2.yzwy, r1.xyzx
  53: mad r2.yzw, r1.xxyz, r0.xxxx, -r1.xxyz
  54: max r0.x, v2.y, l(0)
  55: mul r0.w, r0.x, l(0.200000)
  56: add r0.x, r0.x, l(-0.200000)
  57: mul_sat r0.x, r0.x, l(10.000000)
  58: mad r1.xyz, r0.wwww, r2.yzwy, r1.xyzx
  59: mad r0.w, r0.z, l(-2.000000), l(3.000000)
  60: mul r0.z, r0.z, r0.z
  61: mul r0.z, r0.z, r0.w
  62: mul r0.z, r2.x, r0.z
  63: mul r0.x, r0.x, r0.z
  64: mad_sat r0.xyz, r0.yyyy, r0.xxxx, r1.xyzx
  65: itof r1.xy, cb0[143].xyxx
  66: div r1.zw, v1.xxxz, cb0[116].xxxz
  67: add_sat r1.zw, r1.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
  68: mad r1.xy, r1.zwzz, r1.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  69: sample_l(texture2d)(float,float,float,float) r2.xyz, r1.zwzz, t2.xyzw, s1, l(0)
  70: add r2.xyz, r2.xyzx, -cb0[40].xyzx
  71: round_ni r1.zw, r1.xxxy
  72: frc r1.xy, r1.xyxx
  73: ftoi r1.zw, r1.zzzw
  74: iadd r3.xy, r1.zwzz, l(1, 1, 0, 0)
  75: imax r3.xy, r3.xyxx, l(0, 0, 0, 0)
  76: iadd r3.zw, cb0[143].xxxy, l(0, 0, -1, -1)
  77: imin r3.xy, r3.zwzz, r3.xyxx
  78: imad r0.w, r3.y, cb0[143].x, r3.x
  79: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r0.w, l(4), t1.xyxx
  80: ushr r0.w, r3.x, l(12)
  81: bfi r0.w, l(12), l(20), r3.y, r0.w
  82: and r0.w, r0.w, l(0x003fffff)
  83: utof r0.w, r0.w
  84: iadd r4.xyzw, r1.zwzw, l(1, 0, 0, 1)
  85: imax r1.zw, r1.zzzw, l(0, 0, 0, 0)
  86: imin r1.zw, r3.zzzw, r1.zzzw
  87: imad r1.z, r1.w, cb0[143].x, r1.z
  88: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(4), t1.xxxy
  89: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  90: imin r3.xyzw, r3.zwzw, r4.xyzw
  91: imad r3.xy, r3.ywyy, cb0[143].xxxx, r3.xzxx
  92: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.yz, r3.y, l(4), t1.xxyx
  93: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xw, r3.x, l(4), t1.xxxy
  94: ushr r2.w, r3.y, l(12)
  95: bfi r2.w, l(12), l(20), r3.z, r2.w
  96: and r2.w, r2.w, l(0x003fffff)
  97: utof r2.w, r2.w
  98: mul r2.w, r2.w, l(0.000001)
  99: mad r0.w, r0.w, l(0.000001), -r2.w
 100: mad r0.w, r1.x, r0.w, r2.w
 101: ushr r2.w, r3.x, l(12)
 102: bfi r2.w, l(12), l(20), r3.w, r2.w
 103: and r2.w, r2.w, l(0x003fffff)
 104: utof r2.w, r2.w
 105: ushr r1.z, r1.z, l(12)
 106: bfi r1.z, l(12), l(20), r1.w, r1.z
 107: and r1.z, r1.z, l(0x003fffff)
 108: utof r1.z, r1.z
 109: mul r1.z, r1.z, l(0.000001)
 110: mad r1.w, r2.w, l(0.000001), -r1.z
 111: mad r1.x, r1.x, r1.w, r1.z
 112: add r0.w, r0.w, -r1.x
 113: mad r0.w, r1.y, r0.w, r1.x
 114: mul r0.w, r0.w, l(-0.721348)
 115: exp r0.w, r0.w
 116: mul r1.xyz, v1.yyyy, cb0[135].xyzx
 117: mad r1.xyz, cb0[134].xyzx, v1.xxxx, r1.xyzx
 118: mad r1.xyz, cb0[136].xyzx, v1.zzzz, r1.xyzx
 119: add r1.xyz, r1.xyzx, cb0[137].xyzx
 120: ge r1.w, l(0), r1.z
 121: ge r2.w, r1.z, l(1.000000)
 122: sample_c_lz(texture2d)(float,float,float,float) r1.x, r1.xyxx, t0.xxxx, s0, r1.z
 123: or r1.y, r1.w, r2.w
 124: movc r1.x, r1.y, l(1.000000), r1.x
 125: mul r0.w, r0.w, r1.x
 126: dp3 r1.x, v2.xyzx, -cb0[123].xyzx
 127: max r1.x, r1.x, l(0)
 128: mul r1.xyz, r1.xxxx, cb0[125].xyzx
 129: dp3 r1.w, v2.xyzx, -cb0[124].xyzx
 130: max r1.w, r1.w, l(0)
 131: mul r3.xyz, r1.wwww, cb0[126].xyzx
 132: mad r1.xyz, r1.xyzx, r0.wwww, r3.xyzx
 133: mul r3.xyzw, cb0[116].xxzz, l(0.500000, -0.500000, 0.500000, -0.500000)
 134: lt r3.xz, v1.xxzx, r3.xxzx
 135: lt r3.yw, r3.yyyw, v1.xxxz
 136: and r0.w, r3.y, r3.x
 137: and r0.w, r3.z, r0.w
 138: and r0.w, r3.w, r0.w
 139: and r0.w, r0.w, l(1.000000)
 140: mad r2.xyz, r0.wwww, r2.xyzx, cb0[40].xyzx
 141: mul r2.xyz, r0.xyzx, r2.xyzx
 142: mad o0.xyz, r0.xyzx, r1.xyzx, r2.xyzx
 143: mov o0.w, v1.y
 144: ret
