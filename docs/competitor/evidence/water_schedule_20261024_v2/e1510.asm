Shader hash c7c2926b-05b6f481-5d562878-89bbf12d

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[158], immediateIndexed
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 8
      dcl_thread_group 32, 32, 1
   0: iadd r0.xyzw, vThreadID.xyxy, l(-1, 0, 1, 0)
   1: imax r0.x, r0.x, l(0)
   2: iadd r1.xy, cb0[155].xyxx, l(-1, -1, 0, 0)
   3: imin r0.xy, r0.xyxx, r1.xyxx
   4: imad r0.x, r0.y, cb0[155].x, r0.x
   5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyz, r0.x, l(0), u0.xyzx
   6: imin r0.xy, r0.zwzz, r1.xyxx
   7: imad r0.x, r0.y, cb0[155].x, r0.x
   8: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.x, r0.x, l(8), u0.xxxx
   9: and r0.x, r0.x, l(0.000000)
  10: utof r0.x, r0.x
  11: iadd r3.xyzw, vThreadID.xyxy, l(0, -1, 0, 1)
  12: imax r3.y, r3.y, l(0)
  13: imin r0.yz, r1.xxyx, r3.zzwz
  14: imad r0.y, r0.z, cb0[155].x, r0.y
  15: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.y, r0.y, l(8), u0.xxxx
  16: imin r0.zw, r1.xxxy, r3.xxxy
  17: ige r1.xy, vThreadID.xyxx, r1.xyxx
  18: imad r0.z, r0.w, cb0[155].x, r0.z
  19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(4), u0.xxxy
  20: and r0.yw, r0.yyyw, l(0.000000, 0.000000, 0.000000, 0.000000)
  21: utof r0.yw, r0.yyyw
  22: mul r0.xy, r0.xyxx, l(0.000001, 0.000001, 0.000000, 0.000000)
  23: imad r1.z, vThreadID.y, cb0[155].x, vThreadID.x
  24: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r1.z, l(0), u0.xyzw
  25: ushr r1.w, r2.x, l(16)
  26: bfi r1.w, l(16), l(16), r2.y, r1.w
  27: and r2.x, r2.z, l(0.000000)
  28: utof r2.x, r2.x
  29: mul r2.y, r2.x, l(0.000001)
  30: and r1.w, r1.w, l(0.000000)
  31: utof r1.w, r1.w
  32: mad r2.x, r1.w, l(0.000000), l(-4.000000)
  33: mov r4.w, l(0)
  34: and r5.xyz, r3.xzxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  35: utof r5.xyz, r5.xyzx
  36: mul r4.y, r5.y, l(0.000001)
  37: movc r2.xy, vThreadID.xxxx, r2.xyxx, r4.wyww
  38: add r1.w, r2.y, l(-0.050000)
  39: max r1.w, r1.w, l(0)
  40: movc r0.xy, r1.xyxx, r4.yyyy, r0.xyxx
  41: add r0.xy, r0.xyxx, l(-0.050000, -0.050000, 0.000000, 0.000000)
  42: max r0.xy, r0.xyxx, l(0, 0, 0, 0)
  43: add r1.x, r0.x, r1.w
  44: ushr r0.z, r0.z, l(8)
  45: mul r6.y, r0.w, l(0.000001)
  46: utof r0.z, r0.z
  47: mad r6.x, r0.z, l(0.000000), l(-4.000000)
  48: movc r0.zw, vThreadID.yyyy, r6.xxxy, r4.wwwy
  49: add r0.w, r0.w, l(-0.050000)
  50: max r0.w, r0.w, l(0)
  51: add r1.x, r0.w, r1.x
  52: add r1.x, r0.y, r1.x
  53: add r1.y, cb0[154].x, cb0[154].x
  54: mul r2.y, cb0[157].z, cb0[157].w
  55: div r1.y, r1.y, r2.y
  56: mad r1.x, r1.x, l(0.250000), -r1.y
  57: max r1.x, r1.x, l(0)
  58: ge r1.y, r2.x, l(0)
  59: mad r6.xyz, r5.xyzx, l(0.007843, 0.000001, 1.000000, 0.000000), l(-1.000000, -0.050000, 0.500000, 0.000000)
  60: max r2.y, r6.y, l(0)
  61: movc r1.y, r1.y, r1.w, r2.y
  62: add r1.y, -r1.x, r1.y
  63: mul r1.y, r2.x, r1.y
  64: ushr r7.xyzw, r3.xyzw, l(16, 8, 24, 28)
  65: bfi r2.xz, l(16, 0, 24, 0), l(16, 0, 8, 0), r3.yywy, r7.xxzx
  66: utof r3.yz, r7.yywy
  67: ubfe r3.xw, l(8, 0, 0, 4), l(8, 0, 0, 24), r3.xxxw
  68: utof r3.xw, r3.xxxw
  69: and r2.xz, r2.xxzx, l(0.000000, 0.000000, 0.000000, 0.000000)
  70: utof r2.xz, r2.xxzx
  71: mad r2.xw, r2.xxxx, l(0.000000, 0.000000, 0.000000, 1.000000), l(-4.000000, 0.000000, 0.000000, 0.500000)
  72: add r1.w, r2.z, l(0.500000)
  73: ftou r1.w, r1.w
  74: ge r2.z, l(0), r2.x
  75: movc r0.x, r2.z, r0.x, r2.y
  76: add r0.x, -r1.x, r0.x
  77: mad r0.x, r0.x, r2.x, -r1.y
  78: ge r2.x, r0.z, l(0)
  79: movc r0.w, r2.x, r0.w, r2.y
  80: add r0.w, -r1.x, r0.w
  81: mul r0.z, r0.z, r0.w
  82: mad r2.xz, r3.yyyy, l(0.000000, 0.000000, 1.000000, 0.000000), l(-4.000000, 0.000000, 0.500000, 0.000000)
  83: add r0.w, r3.z, l(0.500000)
  84: ftou r0.w, r0.w
  85: ishl r7.w, r0.w, l(28)
  86: ge r0.w, l(0), r2.x
  87: movc r0.y, r0.w, r0.y, r2.y
  88: add r0.y, -r1.x, r0.y
  89: mad r0.y, r0.y, r2.x, -r0.z
  90: ftou r0.z, r2.z
  91: ishl r0.z, r0.z, l(8)
  92: mul r0.y, r0.y, cb0[154].w
  93: mad r0.x, r0.x, cb0[154].z, r0.y
  94: mad r0.x, -r0.x, cb0[157].z, r4.y
  95: max r0.x, r0.x, cb0[114].y
  96: min r0.x, r0.x, cb0[115].y
  97: mad r0.y, -r5.y, l(0.000001), r0.x
  98: mul_sat r0.x, r0.x, l(0.099010)
  99: mad r0.x, r0.x, l(16777215.000000), l(0.500000)
 100: div r0.y, r0.y, cb0[157].z
 101: mad r2.xy, r3.xxxx, l(0.007843, 1.000000, 0.000000, 0.000000), l(-1.000000, 0.500000, 0.000000, 0.000000)
 102: add r0.w, r3.w, l(0.500000)
 103: ftou r0.xw, r0.xxxw
 104: mov r6.w, r2.x
 105: ftou r1.xy, r2.ywyy
 106: dp2 r2.x, r6.xwxx, r6.xwxx
 107: ftou r2.y, r6.z
 108: imad r1.x, r1.x, l(256), r2.y
 109: bfi r3.x, l(16), l(16), r1.y, r1.x
 110: ushr r1.x, r1.y, l(16)
 111: or r3.y, r0.z, r1.x
 112: sqrt r0.z, r2.x
 113: lt r0.yz, l(0.000000, 0.100000, 0.500000, 0.000000), r0.yyzy
 114: and r0.y, r0.y, r0.z
 115: and r0.y, r0.y, l(0.000000)
 116: ushr r0.z, r1.w, l(8)
 117: ishl r1.x, r1.w, l(24)
 118: or r3.z, r0.x, r1.x
 119: iadd r0.x, r0.y, r0.z
 120: imad r3.w, r0.w, l(0.000000), r0.x
 121: mov r7.xyz, l(0, 0, 0, 0)
 122: iadd r0.xyzw, r7.xyzw, r3.xyzw
 123: store_structured u0.xyzw, r1.z, l(0), r0.xyzw
 124: ret
