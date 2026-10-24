Shader hash 333ca2f4-962a8894-cb8a7f47-6868bff3

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[29], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_input_ps linear v1.xy
      dcl_input_ps linear v1.zw
      dcl_output o0.xyzw
      dcl_temps 3
   0: mad r0.xy, v1.xyxx, cb0[28].xyxx, cb0[28].zwzz
   1: sample_indexable(texture2d)(float,float,float,float) r0.x, r0.xyxx, t0.wxyz, s0
   2: mad r0.x, r0.x, l(2.000000), l(-1.000000)
   3: add r0.y, -abs(r0.x), l(1.000000)
   4: mad_sat r0.x, r0.x, l(340282346638528870000000000000000000000.000000), l(0.500000)
   5: mad r0.x, r0.x, l(2.000000), l(-1.000000)
   6: sqrt r0.y, r0.y
   7: add r0.y, -r0.y, l(1.000000)
   8: mul r0.x, r0.y, r0.x
   9: sample_indexable(texture2d)(float,float,float,float) r1.xyzw, v1.zwzz, t1.xyzw, s1
  10: max r0.yzw, abs(r1.xxyz), l(0.000000, 0.000000, 0.000000, 0.000000)
  11: log r0.yzw, r0.yyzw
  12: mul r0.yzw, r0.yyzw, l(0.000000, 0.416667, 0.416667, 0.416667)
  13: exp r0.yzw, r0.yyzw
  14: mad r0.yzw, r0.yyzw, l(0.000000, 1.055000, 1.055000, 1.055000), l(0.000000, -0.055000, -0.055000, -0.055000)
  15: mul r2.xyz, r1.xyzx, l(12.920000, 12.920000, 12.920000, 0.000000)
  16: ge r1.xyz, l(0.003131, 0.003131, 0.003131, 0.000000), r1.xyzx
  17: mov o0.w, r1.w
  18: movc r0.yzw, r1.xxyz, r2.xxyz, r0.yyzw
  19: mad r0.xyz, r0.xxxx, l(0.003922, 0.003922, 0.003922, 0.000000), r0.yzwy
  20: add r1.xyz, r0.xyzx, l(0.055000, 0.055000, 0.055000, 0.000000)
  21: mul r1.xyz, r1.xyzx, l(0.947867, 0.947867, 0.947867, 0.000000)
  22: max r1.xyz, abs(r1.xyzx), l(0.000000, 0.000000, 0.000000, 0.000000)
  23: log r1.xyz, r1.xyzx
  24: mul r1.xyz, r1.xyzx, l(2.400000, 2.400000, 2.400000, 0.000000)
  25: exp r1.xyz, r1.xyzx
  26: mul r2.xyz, r0.xyzx, l(0.077399, 0.077399, 0.077399, 0.000000)
  27: ge r0.xyz, l(0.040450, 0.040450, 0.040450, 0.000000), r0.xyzx
  28: movc o0.xyz, r0.xyzx, r2.xyzx, r1.xyzx
  29: ret
