Shader hash b79c3c6b-0f40193f-b59ea225-f677649b

ps_4_0
      dcl_constantbuffer cb0[139], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_output o0.x
      dcl_temps 4
   0: mul r0.z, cb0[138].x, l(2.500000)
   1: mov r0.yw, l(0.000000, 2.000000, 0.000000, 0.000000)
   2: add r1.xy, -r0.zwzz, v1.xyxx
   3: add r0.zw, r0.zzzw, v1.xxxy
   4: sample_indexable r2.xyzw, r0.zwzz, t0.xyzw, s0
   5: sample_indexable r1.xyzw, r1.xyxx, t0.xyzw, s0
   6: mul r0.z, r1.x, l(0.233243)
   7: mov r0.x, cb0[138].x
   8: mad r1.xy, -r0.xyxx, l(5.000000, 0.000000, 0.000000, 0.000000), v1.xyxx
   9: mad r0.xy, r0.xyxx, l(5.000000, 0.000000, 0.000000, 0.000000), v1.xyxx
  10: sample_indexable r3.xyzw, r0.xyxx, t0.xyzw, s0
  11: sample_indexable r1.xyzw, r1.xyxx, t0.xyzw, s0
  12: mad r0.x, r1.x, l(0.121622), r0.z
  13: sample_indexable r1.xyzw, v1.xyxx, t0.xyzw, s0
  14: mad r0.x, r1.x, l(0.290272), r0.x
  15: mad r0.x, r2.x, l(0.233243), r0.x
  16: mad o0.x, r3.x, l(0.121622), r0.x
  17: ret
