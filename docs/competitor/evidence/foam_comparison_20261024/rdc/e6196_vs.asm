Shader hash 65ce9c47-1ba2bb03-6d1158ef-c720a2d4

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[66], immediateIndexed
      dcl_constantbuffer cb1[4], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_resource_structured t1, 4
      dcl_input v0.xyz
      dcl_input v1.xy
      dcl_input_sgv v2.x, instanceid
      dcl_output_siv o0.xyzw, position
      dcl_output o1.xyz
      dcl_output o2.xyz
      dcl_temps 2
   0: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.x, v2.x, l(0), t1.xxxx
   1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xyzw, r0.x, l(0), t0.xyzw
   2: mul r1.xy, r0.xxxx, l(10.000000, -5.770780, 0.000000, 0.000000)
   3: exp r0.x, r1.y
   4: mov_sat r1.x, r1.x
   5: mul o2.z, r1.x, l(0.400000)
   6: add r0.x, -r0.x, l(1.000000)
   7: mul r0.x, r0.x, l(0.100000)
   8: mad r0.xyz, v0.xzyx, r0.xxxx, r0.yzwy
   9: add r0.xyz, r0.xyzx, l(0.000000, 0.020000, 0.000000, 0.000000)
  10: mul r1.xyz, r0.yyyy, cb1[1].xyzx
  11: mad r0.xyw, cb1[0].xyxz, r0.xxxx, r1.xyxz
  12: mad r0.xyz, cb1[2].xyzx, r0.zzzz, r0.xywx
  13: add r0.xyz, r0.xyzx, cb1[3].xyzx
  14: mul r1.xyzw, r0.yyyy, cb0[63].xyzw
  15: mad r1.xyzw, cb0[62].xyzw, r0.xxxx, r1.xyzw
  16: mad r1.xyzw, cb0[64].xyzw, r0.zzzz, r1.xyzw
  17: mov o1.xyz, r0.xyzx
  18: add o0.xyzw, r1.xyzw, cb0[65].xyzw
  19: mov o2.xy, v1.xyxx
  20: ret
