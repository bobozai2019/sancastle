Shader hash 1d61effa-41a27afe-5a9e12df-39e40ba2

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[142], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_sampler s3, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture2d (float,float,float,float) t3
      dcl_resource_structured t4, 16
      dcl_resource_texture2d (float,float,float,float) t5
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyzw
      dcl_input_ps linear v4.xy
      dcl_output o0.xyzw
      dcl_temps 7
   0: lt r0.x, v1.y, l(0)
   1: discard_nz r0.x
   2: itof r0.xy, cb0[141].xyxx
   3: div r0.zw, v1.xxxz, cb0[116].xxxz
   4: add_sat r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
   5: mad r0.xy, r0.zwzz, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   6: round_ni r1.xy, r0.xyxx
   7: frc r0.xy, r0.xyxx
   8: ftoi r1.xy, r1.xyxx
   9: iadd r1.zw, r1.xxxy, l(0, 0, 1, 1)
  10: imax r1.zw, r1.zzzw, l(0, 0, 0, 0)
  11: iadd r2.xy, cb0[141].xyxx, l(-1, -1, 0, 0)
  12: imin r1.zw, r1.zzzw, r2.xxxy
  13: imad r1.z, r1.w, cb0[141].x, r1.z
  14: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(4), t4.xxxy
  15: ushr r1.z, r1.z, l(12)
  16: bfi r1.z, l(12), l(20), r1.w, r1.z
  17: and r1.z, r1.z, l(0x003fffff)
  18: iadd r3.xyzw, r1.xyxy, l(1, 0, 0, 1)
  19: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
  20: imin r1.xy, r2.xyxx, r1.xyxx
  21: imad r1.x, r1.y, cb0[141].x, r1.x
  22: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(4), t4.xyxx
  23: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  24: imin r2.xyzw, r2.xyxy, r3.xyzw
  25: imad r2.xy, r2.ywyy, cb0[141].xxxx, r2.xzxx
  26: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.yz, r2.y, l(4), t4.xxyx
  27: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xw, r2.x, l(4), t4.xxxy
  28: ushr r1.w, r2.y, l(12)
  29: bfi r1.w, l(12), l(20), r2.z, r1.w
  30: and r1.w, r1.w, l(0x003fffff)
  31: utof r1.zw, r1.zzzw
  32: mul r1.w, r1.w, l(0.000001)
  33: mad r1.z, r1.z, l(0.000001), -r1.w
  34: mad r1.z, r0.x, r1.z, r1.w
  35: ushr r1.w, r2.x, l(12)
  36: bfi r1.w, l(12), l(20), r2.w, r1.w
  37: and r1.w, r1.w, l(0x003fffff)
  38: ushr r1.x, r1.x, l(12)
  39: bfi r1.x, l(12), l(20), r1.y, r1.x
  40: and r1.x, r1.x, l(0x003fffff)
  41: utof r1.xw, r1.xxxw
  42: mul r1.x, r1.x, l(0.000001)
  43: mad r1.y, r1.w, l(0.000001), -r1.x
  44: mad r0.x, r0.x, r1.y, r1.x
  45: add r1.x, -r0.x, r1.z
  46: mad r0.x, r0.y, r1.x, r0.x
  47: mul r0.x, r0.x, l(-0.721348)
  48: exp r0.x, r0.x
  49: mul r1.xyz, v1.yyyy, cb0[135].xyzx
  50: mad r1.xyz, cb0[134].xyzx, v1.xxxx, r1.xyzx
  51: mad r1.xyz, cb0[136].xyzx, v1.zzzz, r1.xyzx
  52: add r1.xyz, r1.xyzx, cb0[137].xyzx
  53: ge r0.y, l(0), r1.z
  54: ge r1.w, r1.z, l(1.000000)
  55: sample_c_lz(texture2d)(float,float,float,float) r1.x, r1.xyxx, t0.xxxx, s0, r1.z
  56: or r0.y, r0.y, r1.w
  57: movc r0.y, r0.y, l(1.000000), r1.x
  58: mul r0.x, r0.x, r0.y
  59: itof r1.xy, cb0[139].xyxx
  60: mad r1.xy, r0.zwzz, r1.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  61: sample_l(texture2d)(float,float,float,float) r0.yzw, r0.zwzz, t5.wxyz, s3, l(0)
  62: add r0.yzw, r0.yyzw, -cb0[40].xxyz
  63: round_ni r1.zw, r1.xxxy
  64: frc r1.xy, r1.xyxx
  65: ftoi r1.zw, r1.zzzw
  66: iadd r2.xy, r1.zwzz, l(1, 1, 0, 0)
  67: imax r2.xy, r2.xyxx, l(0, 0, 0, 0)
  68: iadd r2.zw, cb0[139].xxxy, l(0, 0, -1, -1)
  69: imin r2.xy, r2.zwzz, r2.xyxx
  70: imad r2.x, r2.y, cb0[139].x, r2.x
  71: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.y, r2.x, l(0), t1.xxxx
  72: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r2.x, l(8), t1.xyxx
  73: and r2.x, r2.y, l(255)
  74: ubfe r2.y, l(8), l(8), r2.y
  75: utof r2.xy, r2.xyxx
  76: mad r4.zw, r2.yyyy, l(0.000000, 0.000000, 0.007843, 0.007843), l(0.000000, 0.000000, -1.000000, -1.000000)
  77: mad r4.xy, r2.xxxx, l(0.007843, 0.007843, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
  78: iadd r5.xyzw, r1.zwzw, l(1, 0, 0, 1)
  79: imax r1.zw, r1.zzzw, l(0, 0, 0, 0)
  80: imin r1.zw, r2.zzzw, r1.zzzw
  81: imad r1.z, r1.w, cb0[139].x, r1.z
  82: imax r5.xyzw, r5.xyzw, l(0, 0, 0, 0)
  83: imin r2.xyzw, r2.zwzw, r5.xyzw
  84: imad r2.xy, r2.ywyy, cb0[139].xxxx, r2.xzxx
  85: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.w, r2.y, l(0), t1.xxxx
  86: and r2.z, r1.w, l(255)
  87: ubfe r1.w, l(8), l(8), r1.w
  88: utof r1.w, r1.w
  89: mad r5.zw, r1.wwww, l(0.000000, 0.000000, 0.007843, 0.007843), l(0.000000, 0.000000, -1.000000, -1.000000)
  90: utof r1.w, r2.z
  91: mad r5.xy, r1.wwww, l(0.007843, 0.007843, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
  92: add r4.xyzw, r4.xyzw, -r5.yyww
  93: mad r4.xyzw, r1.xxxx, r4.xyzw, r5.xyzw
  94: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.w, r2.x, l(0), t1.xxxx
  95: and r2.z, r1.w, l(255)
  96: ubfe r1.w, l(8), l(8), r1.w
  97: utof r1.w, r1.w
  98: mad r5.zw, r1.wwww, l(0.000000, 0.000000, 0.007843, 0.007843), l(0.000000, 0.000000, -1.000000, -1.000000)
  99: utof r1.w, r2.z
 100: mad r5.xy, r1.wwww, l(0.007843, 0.007843, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
 101: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.w, r1.z, l(0), t1.xxxx
 102: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r1.z, l(8), t1.xxxy
 103: and r1.z, r1.w, l(255)
 104: ubfe r1.w, l(8), l(8), r1.w
 105: utof r1.zw, r1.zzzw
 106: mad r6.zw, r1.wwww, l(0.000000, 0.000000, 0.007843, 0.007843), l(0.000000, 0.000000, -1.000000, -1.000000)
 107: mad r6.xy, r1.zzzz, l(0.007843, 0.007843, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
 108: add r5.xyzw, r5.xyzw, -r6.yyww
 109: mad r5.xyzw, r1.xxxx, r5.xyzw, r6.xyzw
 110: add r4.xyzw, r4.xyzw, -r5.yyww
 111: mad r4.xyzw, r1.yyyy, r4.xyzw, r5.xyzw
 112: dp2 r1.z, r4.ywyy, r4.ywyy
 113: mul r4.xyzw, r4.xyzw, l(1.000000, 0.000000, 0.000000, 1.000000)
 114: add r4.xyz, r4.zzwz, r4.xyyx
 115: add r1.z, -r1.z, l(1.000000)
 116: sqrt r1.z, r1.z
 117: mad r4.xyz, r1.zzzz, l(0.000000, 1.000000, 0.000000, 0.000000), r4.xyzx
 118: add r4.xyz, r4.xyzx, -v2.xyzx
 119: ushr r1.z, r3.x, l(12)
 120: bfi r1.z, l(12), l(20), r3.y, r1.z
 121: and r1.z, r1.z, l(0.000000)
 122: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r2.y, l(8), t1.xyxx
 123: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r2.x, l(8), t1.xyxx
 124: ushr r1.w, r3.x, l(12)
 125: bfi r1.w, l(12), l(20), r3.y, r1.w
 126: and r1.w, r1.w, l(0.000000)
 127: utof r1.zw, r1.zzzw
 128: mul r1.w, r1.w, l(0.000001)
 129: mad r1.z, r1.z, l(0.000001), -r1.w
 130: mad r1.z, r1.x, r1.z, r1.w
 131: ushr r1.w, r2.x, l(12)
 132: bfi r1.w, l(12), l(20), r2.y, r1.w
 133: and r1.w, r1.w, l(0.000000)
 134: utof r1.w, r1.w
 135: ushr r2.x, r2.z, l(12)
 136: bfi r2.x, l(12), l(20), r2.w, r2.x
 137: and r2.x, r2.x, l(0.000000)
 138: utof r2.x, r2.x
 139: mul r2.x, r2.x, l(0.000001)
 140: mad r1.w, r1.w, l(0.000001), -r2.x
 141: mad r1.x, r1.x, r1.w, r2.x
 142: add r1.z, -r1.x, r1.z
 143: mad r1.x, r1.y, r1.z, r1.x
 144: add_sat r1.x, -r1.x, v1.y
 145: add r1.x, -r1.x, l(1.000000)
 146: log r1.x, r1.x
 147: mul r1.yz, v1.xxzx, l(0.000000, 0.300000, 0.300000, 0.000000)
 148: sample_indexable(texture2d)(float,float,float,float) r1.yz, r1.yzyy, t3.yxzw, s2
 149: mad r1.z, r1.z, l(100.000000), l(1.000000)
 150: add r1.y, r1.y, r1.y
 151: mad r2.xyz, cb0[127].xyzx, r1.yyyy, -cb0[127].xyzx
 152: mad r2.xyz, r2.xyzx, l(0.400000, 0.400000, 0.400000, 0.000000), cb0[127].xyzx
 153: mul r1.x, r1.x, r1.z
 154: exp r1.x, r1.x
 155: mul r3.xyzw, cb0[116].xxzz, l(0.500000, -0.500000, 0.500000, -0.500000)
 156: lt r1.yz, v1.xxzx, r3.xxzx
 157: lt r3.xy, r3.ywyy, v1.xzxx
 158: and r1.y, r1.y, r3.x
 159: and r1.y, r1.z, r1.y
 160: and r1.y, r3.y, r1.y
 161: and r1.y, r1.y, l(1.000000)
 162: mul r1.x, r1.y, r1.x
 163: mad r0.yzw, r1.yyyy, r0.yyzw, cb0[40].xxyz
 164: log r1.y, r1.x
 165: mul r1.y, r1.y, l(0.300000)
 166: exp r1.y, r1.y
 167: mad r1.yzw, r1.yyyy, r4.xxyz, v2.xxyz
 168: dp3 r2.w, r1.yzwy, -cb0[123].xyzx
 169: dp3 r1.y, r1.yzwy, -cb0[124].xyzx
 170: max r1.y, r1.y, l(0)
 171: mul r1.yzw, r1.yyyy, cb0[126].xxyz
 172: max r2.w, r2.w, l(0)
 173: mul r3.xyz, r2.wwww, cb0[125].xyzx
 174: mad r1.yzw, r3.xxyz, r0.xxxx, r1.yyzw
 175: sample_indexable(texture2d)(float,float,float,float) r0.x, v4.xyxx, t2.xyzw, s1
 176: add r0.x, r0.x, r0.x
 177: mul r3.xyz, v3.xyzx, cb1[0].xyzx
 178: mad r4.xyz, r3.xyzx, r0.xxxx, -r3.xyzx
 179: mad r3.xyz, v3.wwww, r4.xyzx, r3.xyzx
 180: add r2.xyz, r2.xyzx, -r3.xyzx
 181: mad_sat r2.xyz, r1.xxxx, r2.xyzx, r3.xyzx
 182: mad r1.xyz, r2.xyzx, r1.yzwy, cb1[1].xyzx
 183: mad o0.xyz, r0.yzwy, r2.xyzx, r1.xyzx
 184: mov o0.w, v1.y
 185: ret
