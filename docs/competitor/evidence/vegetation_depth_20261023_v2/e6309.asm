Shader hash 3070cb49-f7bab656-91168c22-30076a96

ps_4_0
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
   0: sample_indexable o0.xyzw, v1.xyxx, t0.xyzw, s0
   1: ret
