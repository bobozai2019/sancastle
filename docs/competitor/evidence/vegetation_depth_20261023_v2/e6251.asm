Shader hash 6137f980-9580de3b-61ccdab5-250d230e

ps_4_0
      dcl_constantbuffer cb0[139], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_output o0.x
      dcl_temps 4
   0: mul r0.w, cb0[138].y, l(2.500000)
   1: mov r0.xz, l(0, 0, 0, 0)
   2: add r1.xy, -r0.zwzz, v1.xyxx
   3: add r0.zw, r0.zzzw, v1.xxxy
   4: sample_indexable r2.xyzw, r0.zwzz, t0.xyzw, s0
   5: sample_indexable r1.xyzw, r1.xyxx, t0.xyzw, s0
   6: mul r0.z, r1.x, l(0.233243)
   7: mov r0.y, cb0[138].y
   8: mad r1.xy, l(-2.000000, -5.000000, -0.000000, -0.000000), r0.xyxx, v1.xyxx
   9: mad r0.xy, l(2.000000, 5.000000, 0.000000, 0.000000), r0.xyxx, v1.xyxx
  10: sample_indexable r3.xyzw, r0.xyxx, t0.xyzw, s0
  11: sample_indexable r1.xyzw, r1.xyxx, t0.xyzw, s0
  12: mad r0.x, r1.x, l(0.121622), r0.z
  13: sample_indexable r1.xyzw, v1.xyxx, t0.xyzw, s0
  14: mad r0.x, r1.x, l(0.290272), r0.x
  15: mad r0.x, r2.x, l(0.233243), r0.x
  16: mad o0.x, r3.x, l(0.121622), r0.x
  17: ret
