Shader hash 22e3b796-288ae2d8-ddd6766b-5f65d532

// Note: shader requires additional functionality:
//       Raw and Structured buffers
//
ps_4_0
      dcl_globalFlags refactoringAllowed, enableRawAndStructuredBuffers
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_constantbuffer cb1[1], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyz
      dcl_output o0.xyzw
      dcl_temps 5
   0: lt r0.x, v1.y, l(0)
   1: discard_nz r0.x
   2: div r0.xy, v1.xzxx, cb0[116].xzxx
   3: add_sat r0.xy, r0.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
   4: itof r0.zw, cb0[139].xxxy
   5: mad r0.xy, r0.xyxx, r0.zwzz, l(-0.500000, -0.500000, 0.000000, 0.000000)
   6: round_ni r0.zw, r0.xxxy
   7: frc r0.xy, r0.xyxx
   8: ftoi r0.zw, r0.zzzw
   9: iadd r1.xy, r0.zwzz, l(1, 1, 0, 0)
  10: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
  11: iadd r1.zw, cb0[139].xxxy, l(0, 0, -1, -1)
  12: imin r1.xy, r1.zwzz, r1.xyxx
  13: imad r1.x, r1.y, cb0[139].x, r1.x
  14: ld_structured r2.xy, r1.x, l(4), t1.xyxx
  15: ushr r1.x, r2.x, l(12)
  16: ishl r1.y, r2.y, l(20)
  17: iadd r1.x, r1.y, r1.x
  18: and r1.x, r1.x, l(0x003fffff)
  19: utof r1.x, r1.x
  20: iadd r2.xyzw, r0.zwzw, l(1, 0, 0, 1)
  21: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  22: imin r0.zw, r1.zzzw, r0.zzzw
  23: imad r0.z, r0.w, cb0[139].x, r0.z
  24: ld_structured r3.xy, r0.z, l(4), t1.xyxx
  25: imax r2.xyzw, r2.xyzw, l(0, 0, 0, 0)
  26: imin r2.xyzw, r1.zwzw, r2.xyzw
  27: imad r0.zw, r2.yyyw, cb0[139].xxxx, r2.xxxz
  28: ld_structured r2.xy, r0.w, l(4), t1.xyxx
  29: ld_structured r4.xy, r0.z, l(4), t1.xyxx
  30: ushr r0.z, r2.x, l(12)
  31: ishl r0.w, r2.y, l(20)
  32: iadd r0.z, r0.w, r0.z
  33: and r0.z, r0.z, l(0x003fffff)
  34: utof r0.z, r0.z
  35: mul r0.z, r0.z, l(0.000001)
  36: mad r0.w, r1.x, l(0.000001), -r0.z
  37: mad r0.z, r0.x, r0.w, r0.z
  38: ushr r0.w, r4.x, l(12)
  39: ishl r1.x, r4.y, l(20)
  40: iadd r0.w, r0.w, r1.x
  41: and r0.w, r0.w, l(0x003fffff)
  42: utof r0.w, r0.w
  43: ushr r1.x, r3.x, l(12)
  44: ishl r1.y, r3.y, l(20)
  45: iadd r1.x, r1.y, r1.x
  46: and r1.x, r1.x, l(0x003fffff)
  47: utof r1.x, r1.x
  48: mul r1.x, r1.x, l(0.000001)
  49: mad r0.w, r0.w, l(0.000001), -r1.x
  50: mad r0.x, r0.x, r0.w, r1.x
  51: add r0.z, -r0.x, r0.z
  52: mad r0.x, r0.y, r0.z, r0.x
  53: mul r0.x, r0.x, l(-0.721348)
  54: exp r0.x, r0.x
  55: mul r0.yzw, v1.yyyy, cb0[135].xxyz
  56: mad r0.yzw, cb0[134].xxyz, v1.xxxx, r0.yyzw
  57: mad r0.yzw, cb0[136].xxyz, v1.zzzz, r0.yyzw
  58: add r0.yzw, r0.yyzw, cb0[137].xxyz
  59: ge r1.x, l(0), r0.w
  60: ge r1.y, r0.w, l(1.000000)
  61: sample_c_lz r0.y, r0.yzyy, t0.xxxx, s0, r0.w
  62: or r0.z, r1.y, r1.x
  63: movc r0.y, r0.z, l(1.000000), r0.y
  64: mul r0.x, r0.x, r0.y
  65: dp3 r0.y, v2.xyzx, -cb0[123].xyzx
  66: max r0.y, r0.y, l(0)
  67: mul r0.yzw, r0.yyyy, cb0[125].xxyz
  68: dp3 r1.x, v2.xyzx, -cb0[124].xyzx
  69: max r1.x, r1.x, l(0)
  70: mul r1.xyz, r1.xxxx, cb0[126].xyzx
  71: mad r0.xyz, r0.yzwy, r0.xxxx, r1.xyzx
  72: mul_sat r1.xyz, v3.xyzx, cb1[0].xyzx
  73: mul r2.xyz, r1.xyzx, cb0[40].xyzx
  74: mad o0.xyz, r1.xyzx, r0.xyzx, r2.xyzx
  75: mov o0.w, l(1.000000)
  76: ret
