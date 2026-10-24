Shader hash 2da26b91-e0d3b9d6-11837174-781fd6f3

ps_4_0
      dcl_constantbuffer cb0[31], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.zw
      dcl_output o0.xyzw
      dcl_temps 1
   0: sample_indexable r0.xyzw, v1.zwzz, t0.xyzw, s0
   1: mad r0.x, cb0[21].z, r0.x, cb0[21].w
   2: div r0.x, l(1.000000, 1.000000, 1.000000, 1.000000), r0.x
   3: add r0.y, r0.x, -cb0[30].x
   4: max r0.x, r0.x, l(0.000100)
   5: mul r0.y, r0.y, cb0[30].y
   6: div r0.x, r0.y, r0.x
   7: mul r0.x, r0.x, l(0.500000)
   8: mad r0.x, r0.x, cb0[30].w, l(0.500000)
   9: mov_sat o0.xyzw, r0.xxxx
  10: ret
