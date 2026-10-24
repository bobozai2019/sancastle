Shader hash b8c6a256-5d388d49-193c8acd-bd888c63

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[160], immediateIndexed
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 9
      dcl_thread_group 32, 32, 1
   0: iadd r0.xyzw, vThreadID.xyxy, l(-1, 0, 1, 0)
   1: imax r0.x, r0.x, l(0)
   2: iadd r1.xy, cb0[155].xyxx, l(-1, -1, 0, 0)
   3: imin r0.xyzw, r0.xyzw, r1.xyxy
   4: imad r0.x, r0.y, cb0[155].x, r0.x
   5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xy, r0.x, l(0), u0.xyxx
   6: imad r0.z, r0.w, cb0[155].x, r0.z
   7: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyzw, r0.z, l(0), u0.xyzw
   8: iadd r3.xyzw, vThreadID.xyxy, l(0, -1, 0, 1)
   9: imax r3.y, r3.y, l(0)
  10: imin r0.zw, r1.xxxy, r3.zzzw
  11: imad r0.z, r0.w, cb0[155].x, r0.z
  12: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyzw, r0.z, l(0), u0.xyzw
  13: imin r0.zw, r1.xxxy, r3.xxxy
  14: ige r1.xy, vThreadID.xyxx, r1.xyxx
  15: imad r0.z, r0.w, cb0[155].x, r0.z
  16: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(0), u0.xxxy
  17: imad r1.z, vThreadID.y, cb0[155].x, vThreadID.x
  18: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r1.z, l(0), u0.xyzw
  19: ushr r5.xy, r0.zwzz, l(16, 8, 0, 0)
  20: bfi r0.z, l(16), l(16), r0.w, r5.x
  21: utof r0.w, r5.y
  22: mad r5.y, r0.w, l(0.000000), l(-4.000000)
  23: and r0.z, r0.z, l(0.000000)
  24: utof r0.z, r0.z
  25: mad r5.x, r0.z, l(0.000000), l(-4.000000)
  26: ushr r0.xz, r0.xxyx, l(16, 0, 8, 0)
  27: bfi r0.x, l(16), l(16), r0.y, r0.x
  28: utof r0.y, r0.z
  29: mad r6.y, r0.y, l(0.000000), l(-4.000000)
  30: and r0.x, r0.x, l(0.000000)
  31: utof r0.x, r0.x
  32: mad r6.x, r0.x, l(0.000000), l(-4.000000)
  33: ushr r0.xyz, r2.xyzx, l(16, 8, 24, 0)
  34: bfi r0.xz, l(16, 0, 24, 0), l(16, 0, 8, 0), r2.yywy, r0.xxzx
  35: utof r0.y, r0.y
  36: mad r7.y, r0.y, l(0.000000), l(-4.000000)
  37: and r0.y, r2.z, l(0.000000)
  38: utof r0.y, r0.y
  39: mul r7.z, r0.y, l(0.000001)
  40: and r0.xy, r0.xzxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  41: utof r0.xy, r0.xyxx
  42: mad r7.xw, r0.xxxy, l(0.000000, 0.000000, 0.000000, 0.000001), l(-4.000000, 0.000000, 0.000000, 0.000000)
  43: mov r0.z, l(0)
  44: ushr r2.xyzw, r3.xyzw, l(16, 8, 24, 28)
  45: bfi r2.xz, l(16, 0, 24, 0), l(16, 0, 8, 0), r3.yywy, r2.xxzx
  46: and r2.xz, r2.xxzx, l(0.000000, 0.000000, 0.000000, 0.000000)
  47: utof r2.xyzw, r2.xyzw
  48: mul r0.w, r2.z, l(0.000001)
  49: and r3.yz, r3.zzxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  50: ubfe r8.xyz, l(8, 8, 4, 0), l(8, 16, 24, 0), r3.xwwx
  51: utof r8.xyz, r8.xyzx
  52: utof r3.xy, r3.yzyy
  53: mul r0.x, r3.x, l(0.000001)
  54: movc r7.xyzw, r1.xxxx, r0.zzxw, r7.xyzw
  55: add r1.xw, r6.xxxy, r7.xxxy
  56: add r1.xw, r5.xxxy, r1.xxxw
  57: ushr r5.xyz, r4.xyzx, l(16, 8, 24, 0)
  58: bfi r3.zw, l(0, 0, 16, 24), l(0, 0, 16, 8), r4.yyyw, r5.xxxz
  59: utof r0.y, r5.y
  60: mad r5.y, r0.y, l(0.000000), l(-4.000000)
  61: and r0.y, r4.z, l(0.000000)
  62: utof r0.y, r0.y
  63: mul r5.z, r0.y, l(0.000001)
  64: and r3.zw, r3.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  65: utof r3.zw, r3.zzzw
  66: mad r5.xw, r3.zzzw, l(0.000000, 0.000000, 0.000000, 0.000001), l(-4.000000, 0.000000, 0.000000, 0.000000)
  67: movc r4.xyzw, r1.yyyy, r0.zzxw, r5.xyzw
  68: add r0.xy, r1.xwxx, r4.xyxx
  69: itof r1.xy, vThreadID.xyxx
  70: add r1.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  71: itof r3.zw, cb0[155].xxxy
  72: div_sat r1.xy, r1.xyxx, r3.zwzz
  73: add r3.zw, -r1.xxxy, l(0.000000, 0.000000, 1.000000, 1.000000)
  74: mul r1.xy, r1.xyxx, l(20.000000, 20.000000, 0.000000, 0.000000)
  75: min r1.xy, r1.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
  76: mul r3.zw, r3.zzzw, l(0.000000, 0.000000, 20.000000, 20.000000)
  77: min r3.zw, r3.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000)
  78: mad r4.xy, r3.zwzz, l(-2.000000, -2.000000, 0.000000, 0.000000), l(3.000000, 3.000000, 0.000000, 0.000000)
  79: mul r3.zw, r3.zzzw, r3.zzzw
  80: mul r3.zw, r3.zzzw, r4.xxxy
  81: mad r4.xy, r1.xyxx, l(-2.000000, -2.000000, 0.000000, 0.000000), l(3.000000, 3.000000, 0.000000, 0.000000)
  82: mul r1.xy, r1.xyxx, r1.xyxx
  83: mul r1.xy, r1.xyxx, r4.xyxx
  84: mul r0.z, r3.z, r1.x
  85: mul r0.z, r1.y, r0.z
  86: mad r0.z, -r0.z, r3.w, l(1.000000)
  87: add r1.x, r7.z, l(-0.050000)
  88: max r1.x, r1.x, l(0)
  89: add r1.y, r1.x, r7.w
  90: mad r3.yz, r3.xxyx, l(0.000000, 0.000001, 1.000000, 0.000000), l(0.000000, -0.050000, 0.500000, 0.000000)
  91: add r1.w, r3.x, l(0.500000)
  92: ftou r4.x, r1.w
  93: max r1.w, r3.y, l(0)
  94: ftou r3.x, r3.z
  95: mad r3.y, r2.z, l(0.000001), r1.w
  96: add r5.x, r1.y, -r3.y
  97: lt r1.y, r1.y, r0.w
  98: add r3.z, r4.z, l(-0.050000)
  99: max r3.z, r3.z, l(0)
 100: add r3.w, r3.z, r4.w
 101: lt r4.z, r3.y, r4.w
 102: add r5.y, -r3.y, r3.w
 103: lt r0.w, r3.w, r0.w
 104: lt r3.y, r3.y, r7.w
 105: mul r5.xy, r5.xyxx, cb0[154].zwzz
 106: mul r5.xy, r5.xyxx, -cb0[157].wwww
 107: mad r6.y, r2.y, l(0.000000), l(-4.000000)
 108: add r2.y, r2.w, l(0.500000)
 109: ftou r2.y, r2.y
 110: ishl r7.w, r2.y, l(28)
 111: mad r6.x, r2.x, l(0.000000), l(-4.000000)
 112: add r2.x, r2.z, l(0.500000)
 113: ftou r2.x, r2.x
 114: mad r2.yz, r5.xxyx, cb0[157].zzzz, r6.xxyx
 115: mul r5.xy, r2.yzyy, cb0[159].yyyy
 116: mad r2.yz, -r5.xxyx, cb0[157].zzzz, r2.yyzy
 117: mul r5.xy, r0.zzzz, r2.yzyy
 118: mad r2.yz, -r5.xxyx, cb0[157].zzzz, r2.yyzy
 119: mad r0.xy, r2.yzyy, cb0[159].wwww, r0.xyxx
 120: add r0.z, cb0[159].w, l(4.000000)
 121: div r0.xy, r0.xyxx, r0.zzzz
 122: mul r0.z, cb0[154].x, l(0.000100)
 123: ge r1.xw, r0.zzzz, r1.xxxw
 124: and r1.x, r3.y, r1.x
 125: ge r0.z, r0.z, r3.z
 126: and r0.z, r4.z, r0.z
 127: and r1.y, r1.y, r1.w
 128: and r0.w, r0.w, r1.w
 129: or r0.z, r0.z, r0.w
 130: movc r5.y, r0.z, l(0), r0.y
 131: or r0.y, r1.x, r1.y
 132: movc r5.x, r0.y, l(0), r0.x
 133: mul r0.xy, r5.xyxx, cb0[158].xxxx
 134: dp2 r0.z, r5.xyxx, r5.xyxx
 135: rsq r0.w, r0.z
 136: mul r0.xy, r0.wwww, r0.xyxx
 137: mul r0.w, cb0[158].x, cb0[158].x
 138: lt r0.z, r0.w, r0.z
 139: movc r0.xy, r0.zzzz, r0.xyxx, r5.xyxx
 140: add r0.xy, r0.xyxx, l(4.000000, 4.000000, 0.000000, 0.000000)
 141: mul_sat r0.xy, r0.xyxx, l(0.125000, 0.125000, 0.000000, 0.000000)
 142: mad r0.xy, r0.xyxx, l(16777215.000000, 16777215.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
 143: mad r0.z, r8.x, l(1.000000), l(0.500000)
 144: add r1.xy, r8.yzyy, l(0.500000, 0.500000, 0.000000, 0.000000)
 145: ftou r1.xy, r1.xyxx
 146: ftou r0.xyz, r0.xyzx
 147: imad r0.z, r0.z, l(256), r3.x
 148: bfi r3.x, l(16), l(16), r0.x, r0.z
 149: ushr r0.x, r0.x, l(16)
 150: ishl r0.y, r0.y, l(8)
 151: or r3.y, r0.y, r0.x
 152: ishl r0.x, r2.x, l(24)
 153: ushr r0.y, r2.x, l(8)
 154: mov r4.y, l(0)
 155: iadd r0.xy, r0.xyxx, r4.xyxx
 156: imad r0.y, r1.x, l(0x00010000), r0.y
 157: mov r3.z, r0.x
 158: imad r3.w, r1.y, l(0.000000), r0.y
 159: mov r7.xyz, l(0, 0, 0, 0)
 160: iadd r0.xyzw, r7.xyzw, r3.xyzw
 161: store_structured u0.xyzw, r1.z, l(0), r0.xyzw
 162: ret
