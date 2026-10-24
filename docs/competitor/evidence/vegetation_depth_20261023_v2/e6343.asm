Shader hash 2edb5c94-09c30718-37e6053a-eee058f5

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[31], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 4
   0: mad_sat r0.xyzw, -cb0[28].xyxy, l(0.500000, 0.500000, -0.500000, 0.500000), v1.xyxy
   1: mul r0.xyzw, r0.xyzw, cb0[26].xxxx
   2: sample_indexable(texture2d)(float,float,float,float) r1.xyz, r0.zwzz, t0.xyzw, s0
   3: max r1.w, r1.y, r1.x
   4: max r1.w, r1.z, r1.w
   5: add r1.w, r1.w, l(1.000000)
   6: sample_indexable(texture2d)(float,float,float,float) r0.z, r0.zwzz, t1.yzxw, s1
   7: mad r0.z, r0.z, l(2.000000), l(-1.000000)
   8: div r0.w, abs(r0.z), r1.w
   9: mul r1.xyz, r0.wwww, r1.xyzx
  10: sample_indexable(texture2d)(float,float,float,float) r2.xyz, r0.xyxx, t0.xyzw, s0
  11: sample_indexable(texture2d)(float,float,float,float) r0.x, r0.xyxx, t1.xyzw, s1
  12: mad r0.x, r0.x, l(2.000000), l(-1.000000)
  13: max r0.y, r2.y, r2.x
  14: max r0.y, r2.z, r0.y
  15: add r0.y, r0.y, l(1.000000)
  16: div r0.y, abs(r0.x), r0.y
  17: mad r1.xyz, r2.xyzx, r0.yyyy, r1.xyzx
  18: add r0.y, r0.w, r0.y
  19: mad_sat r2.xyzw, cb0[28].xyxy, l(-0.500000, 0.500000, 0.500000, 0.500000), v1.xyxy
  20: mul r2.xyzw, r2.xyzw, cb0[26].xxxx
  21: sample_indexable(texture2d)(float,float,float,float) r3.xyz, r2.xyxx, t0.xyzw, s0
  22: max r0.w, r3.y, r3.x
  23: max r0.w, r3.z, r0.w
  24: add r0.w, r0.w, l(1.000000)
  25: sample_indexable(texture2d)(float,float,float,float) r1.w, r2.xyxx, t1.yzwx, s1
  26: mad r1.w, r1.w, l(2.000000), l(-1.000000)
  27: div r0.w, abs(r1.w), r0.w
  28: mad r1.xyz, r3.xyzx, r0.wwww, r1.xyzx
  29: add r0.y, r0.w, r0.y
  30: sample_indexable(texture2d)(float,float,float,float) r3.xyz, r2.zwzz, t0.xyzw, s0
  31: sample_indexable(texture2d)(float,float,float,float) r0.w, r2.zwzz, t1.yzwx, s1
  32: mad r0.w, r0.w, l(2.000000), l(-1.000000)
  33: max r2.x, r3.y, r3.x
  34: max r2.x, r3.z, r2.x
  35: add r2.x, r2.x, l(1.000000)
  36: div r2.x, abs(r0.w), r2.x
  37: mad r1.xyz, r3.xyzx, r2.xxxx, r1.xyzx
  38: add r0.y, r0.y, r2.x
  39: max r0.y, r0.y, l(0.000100)
  40: div r1.xyz, r1.xyzx, r0.yyyy
  41: min r0.y, r0.z, r1.w
  42: max r0.z, r0.z, r1.w
  43: max r0.z, r0.w, r0.z
  44: min r0.y, r0.w, r0.y
  45: min r0.y, r0.y, r0.x
  46: max r0.x, r0.z, r0.x
  47: lt r0.z, r0.x, -r0.y
  48: movc r0.x, r0.z, r0.y, r0.x
  49: mul r0.x, r0.x, cb0[30].z
  50: add r0.y, cb0[28].y, cb0[28].y
  51: div r0.y, l(1.000000, 1.000000, 1.000000, 1.000000), r0.y
  52: mul_sat r0.y, r0.y, abs(r0.x)
  53: mov o0.w, r0.x
  54: mad r0.x, r0.y, l(-2.000000), l(3.000000)
  55: mul r0.y, r0.y, r0.y
  56: mul r0.x, r0.y, r0.x
  57: mul o0.xyz, r0.xxxx, r1.xyzx
  58: ret
