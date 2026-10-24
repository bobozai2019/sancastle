Shader hash 891f90cc-c249a1b7-c2c56a82-034d8bdc

ps_4_0
      dcl_constantbuffer cb0[4], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyzw
      dcl_input_ps linear v2.xy
      dcl_output o0.xyzw
      dcl_temps 1
   0: sample_indexable r0.xyzw, v2.xyxx, t0.xyzw, s0
   1: add r0.xyzw, r0.xyzw, cb0[3].xyzw
   2: mul o0.xyzw, r0.xyzw, v1.xyzw
   3: ret
