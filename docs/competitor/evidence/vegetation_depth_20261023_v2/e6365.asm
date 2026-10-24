Shader hash c30f50f6-0cad480f-2c6f5c4a-735ee4ff

ps_4_0
      dcl_constantbuffer cb0[29], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 3
   0: mad_sat r0.xyzw, -cb0[28].xyxy, l(0.500000, 0.500000, -0.500000, 0.500000), v1.xyxy
   1: mul r0.xyzw, r0.xyzw, cb0[26].xxxx
   2: sample_indexable r1.xyzw, r0.xyxx, t0.xyzw, s0
   3: sample_indexable r0.xyzw, r0.zwzz, t0.xyzw, s0
   4: add r0.xyzw, r0.xyzw, r1.xyzw
   5: mad_sat r1.xyzw, cb0[28].xyxy, l(-0.500000, 0.500000, 0.500000, 0.500000), v1.xyxy
   6: mul r1.xyzw, r1.xyzw, cb0[26].xxxx
   7: sample_indexable r2.xyzw, r1.xyxx, t0.xyzw, s0
   8: sample_indexable r1.xyzw, r1.zwzz, t0.xyzw, s0
   9: add r0.xyzw, r0.xyzw, r2.xyzw
  10: add r0.xyzw, r1.xyzw, r0.xyzw
  11: mul o0.xyzw, r0.xyzw, l(0.250000, 0.250000, 0.250000, 0.250000)
  12: ret
