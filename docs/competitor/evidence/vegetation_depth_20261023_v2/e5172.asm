Shader hash a3faf49c-39b84cfe-815ae3ca-4dd689d8

ps_4_0
      dcl_constantbuffer cb0[138], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyz
      dcl_output o0.xyzw
      dcl_temps 3
   0: mul r0.xy, cb0[116].xzxx, l(0.500000, 0.500000, 0.000000, 0.000000)
   1: lt r0.xy, r0.xyxx, abs(v1.xzxx)
   2: discard_nz r0.x
   3: discard_nz r0.y
   4: lt r0.x, v1.y, l(0)
   5: discard_nz r0.x
   6: mul r0.xyz, v1.yyyy, cb0[135].xyzx
   7: mad r0.xyz, cb0[134].xyzx, v1.xxxx, r0.xyzx
   8: mad r0.xyz, cb0[136].xyzx, v1.zzzz, r0.xyzx
   9: add r0.xyz, r0.xyzx, cb0[137].xyzx
  10: ge r0.w, l(0), r0.z
  11: ge r1.x, r0.z, l(1.000000)
  12: sample_c_lz r0.x, r0.xyxx, t0.xxxx, s0, r0.z
  13: or r0.y, r0.w, r1.x
  14: movc r0.x, r0.y, l(1.000000), r0.x
  15: dp3 r0.y, v2.xyzx, -cb0[123].xyzx
  16: max r0.y, r0.y, l(0)
  17: mul r0.yzw, r0.yyyy, cb0[125].xxyz
  18: dp3 r1.x, v2.xyzx, -cb0[124].xyzx
  19: max r1.x, r1.x, l(0)
  20: mul r1.xyz, r1.xxxx, cb0[126].xyzx
  21: mad r0.xyz, r0.yzwy, r0.xxxx, r1.xyzx
  22: mov_sat r1.xyz, v3.xyzx
  23: mul r2.xyz, r1.xyzx, cb0[40].xyzx
  24: mad o0.xyz, r1.xyzx, r0.xyzx, r2.xyzx
  25: mov o0.w, l(1.000000)
  26: ret
