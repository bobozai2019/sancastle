Shader hash 42dfbb50-f772641b-ad703c5b-f1812af4

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[160], immediateIndexed
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 6
      dcl_thread_group 32, 32, 1
   0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
   1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0), u0.xyzw
   2: itof r0.yz, vThreadID.xxyx
   3: add r0.yz, r0.yyzy, l(0.000000, 0.500000, 0.500000, 0.000000)
   4: itof r2.xy, cb0[155].xyxx
   5: div_sat r0.yz, r0.yyzy, r2.xxyx
   6: itof r2.xy, cb0[157].xyxx
   7: mad r0.yw, r0.yyyz, r2.xxxy, l(0.000000, -0.500000, 0.000000, -0.500000)
   8: mul r0.z, r0.z, l(0.037800)
   9: mad r0.z, cb0[113].z, l(8.000000), r0.z
  10: sincos r0.z, null, r0.z
  11: round_ni r2.xy, r0.ywyy
  12: frc r0.yw, r0.yyyw
  13: ftoi r2.xy, r2.xyxx
  14: iadd r2.zw, r2.xxxy, l(0, 0, 1, 1)
  15: imax r2.zw, r2.zzzw, l(0, 0, 0, 0)
  16: iadd r3.xy, cb0[157].xyxx, l(-1, -1, 0, 0)
  17: imin r2.zw, r2.zzzw, r3.xxxy
  18: imad r2.z, r2.w, cb0[157].x, r2.z
  19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r2.z, l(4), t1.xxxy
  20: ushr r2.z, r2.z, l(12)
  21: bfi r2.z, l(12), l(20), r2.w, r2.z
  22: and r2.z, r2.z, l(0x003fffff)
  23: iadd r4.xyzw, r2.xyxy, l(1, 0, 0, 1)
  24: imax r2.xy, r2.xyxx, l(0, 0, 0, 0)
  25: imin r2.xy, r3.xyxx, r2.xyxx
  26: imad r2.x, r2.y, cb0[157].x, r2.x
  27: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r2.x, l(4), t1.xyxx
  28: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  29: imin r3.xyzw, r3.xyxy, r4.xyzw
  30: imad r3.xy, r3.ywyy, cb0[157].xxxx, r3.xzxx
  31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.yz, r3.y, l(4), t1.xxyx
  32: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xw, r3.x, l(4), t1.xxxy
  33: ushr r2.w, r3.y, l(12)
  34: bfi r2.w, l(12), l(20), r3.z, r2.w
  35: and r2.w, r2.w, l(0x003fffff)
  36: utof r2.zw, r2.zzzw
  37: mul r2.w, r2.w, l(0.000001)
  38: mad r2.z, r2.z, l(0.000001), -r2.w
  39: mad r2.z, r0.y, r2.z, r2.w
  40: ushr r2.w, r3.x, l(12)
  41: bfi r2.w, l(12), l(20), r3.w, r2.w
  42: and r2.w, r2.w, l(0x003fffff)
  43: ushr r2.x, r2.x, l(12)
  44: bfi r2.x, l(12), l(20), r2.y, r2.x
  45: and r2.x, r2.x, l(0x003fffff)
  46: utof r2.xw, r2.xxxw
  47: mul r2.x, r2.x, l(0.000001)
  48: mad r2.y, r2.w, l(0.000001), -r2.x
  49: mad r0.y, r0.y, r2.y, r2.x
  50: add r2.x, -r0.y, r2.z
  51: mad r0.y, r0.w, r2.x, r0.y
  52: mul r0.y, r0.y, l(-0.721348)
  53: exp r0.y, r0.y
  54: mul r0.w, cb0[125].x, cb0[158].y
  55: mul r0.w, r0.w, l(0.001000)
  56: mul r0.y, r0.y, r0.w
  57: and r2.xy, r1.xzxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  58: utof r2.xy, r2.xyxx
  59: mul r0.w, r2.y, l(0.000001)
  60: mad r0.y, -r0.y, cb0[157].z, r0.w
  61: mad r0.w, r2.y, l(0.000001), l(-0.050000)
  62: add r2.x, r2.x, l(0.500000)
  63: max r0.w, r0.w, l(0)
  64: ushr r3.xyzw, r1.xyzw, l(16, 8, 24, 28)
  65: bfi r1.yz, l(0, 16, 24, 0), l(0, 16, 8, 0), r1.yywy, r3.xxzx
  66: utof r2.yz, r3.yywy
  67: ubfe r3.xyz, l(8, 8, 4, 0), l(8, 16, 24, 0), r1.xwwx
  68: utof r3.xyz, r3.xyzx
  69: and r1.xy, r1.yzyy, l(0.000000, 0.000000, 0.000000, 0.000000)
  70: utof r1.xy, r1.xyxx
  71: mad r0.w, r1.y, l(0.000001), r0.w
  72: mov r4.xy, vThreadID.xyxx
  73: mov r4.zw, l(0, 0, 0, 0)
  74: ld_indexable(texture2d)(float,float,float,float) r1.z, r4.xyzw, t0.xzyw
  75: ge r1.w, r0.w, r1.z
  76: add r0.w, -r0.w, r1.z
  77: lt r0.w, r0.w, l(0.100000)
  78: mul r2.w, r1.y, l(0.000001)
  79: lt r1.z, r2.w, r1.z
  80: and r1.z, r1.z, r1.w
  81: and r0.w, r0.w, r1.z
  82: and r0.w, r0.w, l(1.000000)
  83: mul r0.z, r0.w, r0.z
  84: mul r0.z, r0.z, cb0[157].z
  85: mad r0.y, r0.z, l(0.150000), r0.y
  86: sincos r0.z, null, cb0[113].z
  87: mul r0.z, r0.z, cb0[158].w
  88: max r0.z, r0.z, l(-0.500000)
  89: mad r0.w, -r1.y, l(0.000001), cb0[159].z
  90: add r0.z, r0.z, r0.w
  91: max r0.z, r0.z, l(0.050000)
  92: add r0.z, -r0.y, r0.z
  93: mul r0.w, r2.z, l(0.066667)
  94: add r1.zw, r2.yyyz, l(0.000000, 0.000000, 0.500000, 0.500000)
  95: ftou r1.zw, r1.zzzw
  96: ishl r4.xy, r1.zwzz, l(8, 28, 0, 0)
  97: mad r0.y, r0.w, r0.z, r0.y
  98: add r0.z, cb0[159].z, cb0[159].x
  99: mad r0.z, -r1.y, l(0.000001), r0.z
 100: add r1.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
 101: ftou r1.xy, r1.xyxx
 102: add r0.z, -r0.y, r0.z
 103: mad r0.z, r0.w, r0.z, r0.y
 104: lt r0.w, l(0), cb0[159].x
 105: movc r0.y, r0.w, r0.z, r0.y
 106: lt r0.z, l(1.050000), r3.z
 107: and r0.z, r0.z, l(1.000000)
 108: mul r0.w, r3.z, l(0.066667)
 109: add r2.yzw, r3.xxyz, l(0.000000, 0.500000, 0.500000, 0.500000)
 110: ftou r2.xyzw, r2.xyzw
 111: mul r0.z, r0.z, r0.w
 112: mad r0.y, r0.z, cb0[157].z, r0.y
 113: max r0.y, r0.y, cb0[114].y
 114: min r0.y, r0.y, cb0[115].y
 115: mul_sat r0.y, r0.y, l(0.099010)
 116: mad r0.y, r0.y, l(16777215.000000), l(0.500000)
 117: ftou r3.x, r0.y
 118: mov r3.y, l(0)
 119: ishl r5.x, r1.y, l(24)
 120: ushr r5.yz, r1.xxyx, l(0, 16, 8, 0)
 121: or r3.xz, r3.yyxy, r5.zzxz
 122: or r3.y, r4.x, r5.y
 123: imad r0.y, r2.z, l(0x00010000), r3.x
 124: imad r3.w, r2.w, l(0.000000), r0.y
 125: imad r0.y, r2.y, l(256), r2.x
 126: bfi r3.x, l(16), l(16), r1.x, r0.y
 127: mov r4.z, l(0)
 128: iadd r1.xyzw, r4.zzzy, r3.xyzw
 129: store_structured u0.xyzw, r0.x, l(0), r1.xyzw
 130: ret
