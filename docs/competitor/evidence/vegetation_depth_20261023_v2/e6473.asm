Shader hash fb782c21-927a1822-4243b9e4-0a3f2cea

ps_4_0
      dcl_constantbuffer cb0[23], immediateIndexed
      dcl_constantbuffer cb1[1], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.xyzw
      dcl_input_ps linear v2.xy
      dcl_input_ps linear v3.xyz
      dcl_input_ps linear v6.xyzw
      dcl_output o0.xyzw
      dcl_temps 4
   0: sample_indexable r0.xyzw, v2.xyxx, t0.xyzw, s2
   1: add r0.x, r0.w, -v3.x
   2: add r0.y, -r0.w, v3.z
   3: lt r0.x, r0.x, l(0)
   4: discard_nz r0.x
   5: mul r0.x, cb0[6].x, cb0[22].w
   6: mul r0.x, r0.x, v3.y
   7: min r0.z, r0.x, l(1.000000)
   8: mul r0.x, r0.x, l(0.500000)
   9: sqrt r0.z, r0.z
  10: mad_sat r0.w, r0.y, v3.y, r0.x
  11: mad r0.x, r0.y, v3.y, -r0.x
  12: mul r0.y, r0.z, r0.w
  13: mad r0.zw, cb0[4].zzzw, cb1[0].yyyy, v6.zzzw
  14: sample_indexable r1.xyzw, r0.zwzz, t2.xyzw, s1
  15: mul r1.xyzw, r1.xyzw, cb0[5].xyzw
  16: mul r1.xyz, r1.wwww, r1.xyzx
  17: mul r2.xyz, v1.xyzx, cb0[3].xyzx
  18: mad r0.zw, cb0[2].xxxy, cb1[0].yyyy, v6.xxxy
  19: sample_indexable r3.xyzw, r0.zwzz, t1.xyzw, s0
  20: mul r2.xyz, r2.xyzx, r3.xyzx
  21: mul r3.w, r3.w, cb0[3].w
  22: mul r3.xyz, r2.xyzx, r3.wwww
  23: add r1.xyzw, r1.xyzw, -r3.xyzw
  24: mad r1.xyzw, r0.yyyy, r1.xyzw, r3.xyzw
  25: mul r0.y, cb0[4].y, cb0[22].w
  26: mul r0.z, r0.y, v3.y
  27: mad r0.y, r0.y, v3.y, l(1.000000)
  28: mad r0.x, r0.z, l(0.500000), r0.x
  29: div_sat r0.x, r0.x, r0.y
  30: add r0.x, -r0.x, l(1.000000)
  31: mul r0.xyzw, r0.xxxx, r1.xyzw
  32: mul o0.xyzw, r0.xyzw, v1.wwww
  33: ret
