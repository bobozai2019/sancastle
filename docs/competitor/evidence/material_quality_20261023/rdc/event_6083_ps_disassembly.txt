Shader hash da7021c5-8327532f-c59fa3a2-a2ea354e

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[138], immediateIndexed
      dcl_constantbuffer cb1[1], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_sampler s3, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture2d (float,float,float,float) t3
      dcl_input_ps_siv linear noperspective v0.xyz, position
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v4.xyw
      dcl_output o0.xyzw
      dcl_temps 5
   0: add r0.x, v4.w, l(-0.000010)
   1: lt r0.x, r0.x, l(0)
   2: discard_nz r0.x
   3: mul r0.xy, v1.xzxx, l(0.050000, 0.050000, 0.000000, 0.000000)
   4: sample_indexable(texture2d)(float,float,float,float) r0.x, r0.xyxx, t3.zxyw, s3
   5: mad r0.x, cb0[113].y, l(0.800000), r0.x
   6: add r0.y, r0.x, l(0.500000)
   7: ge r0.z, r0.y, -r0.y
   8: movc r0.z, r0.z, l(1.000000), l(-1.000000)
   9: mul r0.y, r0.z, r0.y
  10: frc r0.y, r0.y
  11: dp2 r0.y, r0.zzzz, r0.yyyy
  12: add r0.y, r0.y, l(-1.000000)
  13: max r0.zw, v4.xxxy, l(0.000000, 0.000000, -0.500000, -0.500000)
  14: min r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
  15: mad r1.xy, -r0.zwzz, r0.yyyy, v1.xzxx
  16: mad r1.xy, r1.xyxx, l(0.200000, 0.200000, 0.000000, 0.000000), l(0.250000, 0.250000, 0.000000, 0.000000)
  17: sample_indexable(texture2d)(float,float,float,float) r1.xy, r1.xyxx, t3.xyzw, s3
  18: ge r0.y, r0.x, -r0.x
  19: movc r0.y, r0.y, l(1.000000), l(-1.000000)
  20: mul r0.x, r0.y, r0.x
  21: frc r0.x, r0.x
  22: mul r1.z, r0.x, r0.y
  23: mad r0.x, r0.y, r0.x, l(-0.500000)
  24: add r0.x, abs(r0.x), abs(r0.x)
  25: mad r0.y, r1.z, l(2.000000), l(-1.000000)
  26: mad r0.yz, -r0.zzwz, r0.yyyy, v1.xxzx
  27: mad r0.yz, r0.yyzy, l(0.000000, 0.200000, 0.200000, 0.000000), l(0.000000, -0.250000, -0.250000, 0.000000)
  28: sample_indexable(texture2d)(float,float,float,float) r0.yz, r0.yzyy, t3.zxyw, s3
  29: add r1.xyzw, -r0.yyzz, r1.xxyy
  30: mad r0.xyzw, r0.xxxx, r1.xyzw, r0.yyzz
  31: mad r0.xyzw, r0.xyzw, l(2.000000, 2.000000, 2.000000, 2.000000), l(-1.000000, -1.000000, -1.000000, -1.000000)
  32: dp2 r1.x, r0.ywyy, r0.ywyy
  33: mul r0.xyzw, r0.xyzw, l(1.000000, 0.000000, 0.000000, 1.000000)
  34: add r0.xyz, r0.zzwz, r0.xyyx
  35: add r0.w, -r1.x, l(1.000000)
  36: sqrt r0.w, r0.w
  37: mad r0.xyz, r0.wwww, l(0.000000, 1.000000, 0.000000, 0.000000), r0.xyzx
  38: add r0.xyz, r0.xyzx, v2.xyzx
  39: dp3 r0.w, r0.xyzx, r0.xyzx
  40: rsq r0.w, r0.w
  41: mul r0.xyz, r0.wwww, r0.xyzx
  42: mul r1.xy, r0.xzxx, cb1[0].xxxx
  43: div r0.w, cb0[8].x, abs(cb0[8].y)
  44: mul r1.z, r0.w, r1.y
  45: rcp r1.yw, cb0[5].xxxy
  46: mul r2.xy, r1.ywyy, v0.xyxx
  47: mad r0.w, r2.y, cb0[12].x, cb0[12].y
  48: add r2.z, -r0.w, l(1.000000)
  49: add r1.xy, r1.xzxx, r2.xzxx
  50: add r1.zw, -r1.xxxy, r2.xxxz
  51: sample_indexable(texture2d)(float,float,float,float) r0.w, r1.xyxx, t2.yzwx, s2
  52: mad r0.w, cb0[9].z, r0.w, cb0[9].w
  53: div r0.w, l(1.000000, 1.000000, 1.000000, 1.000000), r0.w
  54: mad r2.x, cb0[9].z, v0.z, cb0[9].w
  55: div r2.x, l(1.000000, 1.000000, 1.000000, 1.000000), r2.x
  56: add r0.w, r0.w, -r2.x
  57: lt r0.w, r0.w, l(0)
  58: and r0.w, r0.w, l(1.000000)
  59: mad r1.xy, r0.wwww, r1.zwzz, r1.xyxx
  60: mad r1.zw, r1.xxxy, l(0.000000, 0.000000, 2.000000, 2.000000), l(0.000000, 0.000000, -1.000000, -1.000000)
  61: mul r2.xyzw, -r1.wwww, cb0[67].xyzw
  62: mad r2.xyzw, cb0[66].xyzw, r1.zzzz, r2.xyzw
  63: sample_indexable(texture2d)(float,float,float,float) r0.w, r1.xyxx, t2.yzwx, s2
  64: sample_indexable(texture2d)(float,float,float,float) r1.xyz, r1.xyxx, t1.xyzw, s1
  65: mad r2.xyzw, cb0[68].xyzw, r0.wwww, r2.xyzw
  66: add r2.xyzw, r2.xyzw, cb0[69].xyzw
  67: div r2.xyz, r2.xyzx, r2.wwww
  68: add r2.xyz, r2.xyzx, -v1.xyzx
  69: dp3 r0.w, r2.xyzx, r2.xyzx
  70: sqrt r0.w, r0.w
  71: mul r2.xyz, -r0.wwww, cb0[132].xyzx
  72: mul r2.xyz, r2.xyzx, l(8.656170, 8.656170, 8.656170, 0.000000)
  73: exp r2.xyz, r2.xyzx
  74: mul r2.xyz, r2.xyzx, cb0[131].xyzx
  75: mul r1.xyz, r1.xyzx, r2.xyzx
  76: add r2.xyz, -v1.xyzx, cb0[6].xyzx
  77: dp3 r0.w, r2.xyzx, r2.xyzx
  78: rsq r0.w, r0.w
  79: mul r3.xyz, r0.wwww, r2.xyzx
  80: mad r2.xyz, r2.xyzx, r0.wwww, -cb0[123].xyzx
  81: dp3_sat r0.w, r3.xyzx, r0.xyzx
  82: mul r1.w, r0.w, r0.w
  83: add r0.w, -r0.w, l(1.000000)
  84: mul r2.w, r1.w, r1.w
  85: mul r1.w, r1.w, r2.w
  86: mul r3.xyz, r1.wwww, r1.xyzx
  87: mul r3.xyz, r3.xyzx, l(0.200000, 0.200000, 0.200000, 0.000000)
  88: mad r1.xyz, r1.xyzx, l(0.900000, 0.900000, 0.900000, 0.000000), r3.xyzx
  89: add r3.xyz, -r1.xyzx, cb0[121].xyzx
  90: mul r1.w, r0.w, r0.w
  91: mul r1.w, r1.w, r1.w
  92: mul r0.w, r0.w, r1.w
  93: mul r4.xyz, v1.yyyy, cb0[135].xyzx
  94: mad r4.xyz, cb0[134].xyzx, v1.xxxx, r4.xyzx
  95: mad r4.xyz, cb0[136].xyzx, v1.zzzz, r4.xyzx
  96: add r4.xyz, r4.xyzx, cb0[137].xyzx
  97: ge r1.w, l(0), r4.z
  98: ge r2.w, r4.z, l(1.000000)
  99: sample_c_lz(texture2d)(float,float,float,float) r3.w, r4.xyxx, t0.xxxx, s0, r4.z
 100: or r1.w, r1.w, r2.w
 101: movc r1.w, r1.w, l(1.000000), r3.w
 102: add r2.w, r1.w, l(0.250000)
 103: min r2.w, r2.w, l(1.000000)
 104: mul r0.w, r0.w, r2.w
 105: mul r0.w, r0.w, l(0.750000)
 106: mad r1.xyz, r0.wwww, r3.xyzx, r1.xyzx
 107: dp3 r0.w, r2.xyzx, r2.xyzx
 108: max r0.w, r0.w, l(0.000000)
 109: rsq r0.w, r0.w
 110: mul r2.xyz, r0.wwww, r2.xyzx
 111: dp3_sat r0.x, r0.xyzx, r2.xyzx
 112: log r0.x, r0.x
 113: mul r0.x, r0.x, l(1500.000000)
 114: exp r0.x, r0.x
 115: mul r0.xyz, r0.xxxx, cb0[125].xyzx
 116: mad o0.xyz, r0.xyzx, r1.wwww, r1.xyzx
 117: mul_sat o0.w, v4.w, l(100.000000)
 118: ret
