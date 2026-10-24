Shader hash 47621f14-a2b7448e-45ef93c1-e3822dde

ps_4_0
      dcl_constantbuffer cb0[138], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyz
      dcl_output o0.xyzw
      dcl_temps 3
   0: dp3 r0.x, v1.xyzx, v1.xyzx
   1: rsq r0.x, r0.x
   2: mul r0.xyz, r0.xxxx, v1.xyzx
   3: div r0.w, -cb0[6].y, r0.y
   4: mad r1.xyz, r0.xyzx, r0.wwww, cb0[6].xyzx
   5: ge r0.x, r0.w, l(0)
   6: and r0.xzw, r1.xxyz, r0.xxxx
   7: ge r1.x, abs(r0.y), l(0.000001)
   8: log r0.y, abs(r0.y)
   9: mul r0.y, r0.y, l(1.500000)
  10: exp r0.y, r0.y
  11: and r0.xzw, r0.xxzw, r1.xxxx
  12: mul r1.xyz, r0.zzzz, cb0[135].xyzx
  13: mad r1.xyz, cb0[134].xyzx, r0.xxxx, r1.xyzx
  14: mad r1.xyz, cb0[136].xyzx, r0.wwww, r1.xyzx
  15: add r0.xz, abs(r0.xxwx), -cb0[118].xxzx
  16: max r0.xz, r0.xxzx, l(0, 0, 0, 0)
  17: dp2 r0.x, r0.xzxx, r0.xzxx
  18: sqrt r0.x, r0.x
  19: add r1.xyz, r1.xyzx, cb0[137].xyzx
  20: ge r0.z, l(0), r1.z
  21: ge r0.w, r1.z, l(1.000000)
  22: sample_c_lz r1.x, r1.xyxx, t0.xxxx, s0, r1.z
  23: or r0.z, r0.w, r0.z
  24: movc r0.z, r0.z, l(1.000000), r1.x
  25: mul r0.w, r0.x, l(0.050000)
  26: ge r0.x, l(2.000000), r0.x
  27: and r0.x, r0.x, l(1.000000)
  28: min r0.w, r0.w, l(1.000000)
  29: log r0.w, r0.w
  30: mul r1.xy, r0.wwww, l(0.300000, 1.500000, 0.000000, 0.000000)
  31: exp r1.xy, r1.xyxx
  32: add r0.z, r0.z, r1.y
  33: add r0.w, -cb0[123].y, l(-0.100000)
  34: mul_sat r0.w, r0.w, l(-13.333333)
  35: mad r1.y, r0.w, l(-2.000000), l(3.000000)
  36: mul r0.w, r0.w, r0.w
  37: mad r0.z, r1.y, r0.w, r0.z
  38: min r0.z, r0.z, l(1.000000)
  39: mad r1.yzw, cb0[122].xxyz, cb0[125].xxyz, cb0[40].xxyz
  40: mul r2.xyz, r0.yyyy, r1.yzwy
  41: mad r1.yzw, r2.xxyz, l(0.000000, -0.800000, -0.800000, -0.800000), r1.yyzw
  42: mul r0.xyw, r0.xxxx, r1.yzyw
  43: mad r0.xyw, r0.xyxw, l(-0.200000, -0.200000, 0.000000, -0.200000), r1.yzyw
  44: mul r1.xyz, r1.xxxx, r0.xywx
  45: mul r1.xyz, r1.xyzx, l(0.800000, 0.800000, 0.800000, 0.000000)
  46: mad r0.xyw, r0.xyxw, l(0.200000, 0.200000, 0.000000, 0.200000), r1.xyxz
  47: mul r1.xyz, r0.zzzz, r0.xywx
  48: mul r1.xyz, r1.xyzx, l(0.300000, 0.300000, 0.300000, 0.000000)
  49: mad o0.xyz, r0.xywx, l(0.700000, 0.700000, 0.700000, 0.000000), r1.xyzx
  50: mov o0.w, l(1.000000)
  51: ret
