Shader hash 80089313-953e65ff-0508b096-e686691a

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[138], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_output o0.xyzw
      dcl_temps 3
   0: mul r0.xy, cb0[116].xzxx, l(0.500000, 0.500000, 0.000000, 0.000000)
   1: lt r0.xy, r0.xyxx, abs(v1.xzxx)
   2: discard_nz r0.x
   3: discard_nz r0.y
   4: lt r0.z, v1.y, l(0)
   5: discard_nz r0.z
   6: discard_nz r0.z
   7: add r0.zw, v2.xxxy, l(0.000000, 0.000000, -0.500000, -0.500000)
   8: dp2 r0.z, r0.zwzz, r0.zwzz
   9: sqrt r0.z, r0.z
  10: add r0.z, -r0.z, l(0.500000)
  11: lt r0.z, r0.z, l(0)
  12: discard_nz r0.z
  13: discard_nz r0.x
  14: discard_nz r0.y
  15: mul r0.xyz, v1.yyyy, cb0[135].xyzx
  16: mad r0.xyz, cb0[134].xyzx, v1.xxxx, r0.xyzx
  17: mad r0.xyz, cb0[136].xyzx, v1.zzzz, r0.xyzx
  18: add r0.xyz, r0.xyzx, cb0[137].xyzx
  19: ge r0.w, l(0), r0.z
  20: ge r1.x, r0.z, l(1.000000)
  21: sample_c_lz(texture2d)(float,float,float,float) r0.x, r0.xyxx, t0.xxxx, s0, r0.z
  22: or r0.y, r0.w, r1.x
  23: movc r0.x, r0.y, l(1.000000), r0.x
  24: max r0.y, -cb0[123].y, l(0)
  25: mul r0.yzw, r0.yyyy, cb0[125].xxyz
  26: max r1.x, -cb0[124].y, l(0)
  27: mul r1.xyz, r1.xxxx, cb0[126].xyzx
  28: mad r0.xyz, r0.yzwy, r0.xxxx, r1.xyzx
  29: add r1.xyz, -cb1[0].xyzx, cb1[1].xyzx
  30: mad_sat r1.xyz, v2.zzzz, r1.xyzx, cb1[0].xyzx
  31: mul r2.xyz, r1.xyzx, cb0[40].xyzx
  32: mad o0.xyz, r1.xyzx, r0.xyzx, r2.xyzx
  33: mov o0.w, l(1.000000)
  34: ret
