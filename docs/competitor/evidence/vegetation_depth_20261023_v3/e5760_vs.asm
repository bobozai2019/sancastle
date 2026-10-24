Shader hash a3725ce5-956ebccd-4375fbeb-82c9f4ec

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[66], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_resource_structured t0, 48
      dcl_resource_structured t1, 4
      dcl_input v0.xyz
      dcl_input v1.xyz
      dcl_input_sgv v2.x, instanceid
      dcl_output_siv o0.xyzw, position
      dcl_output o1.xyz
      dcl_output o2.xyz
      dcl_output o3.xyz
      dcl_output o4.xyzw
      dcl_temps 5
   0: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.x, v2.x, l(0), t1.xxxx
   1: ld_structured_indexable(structured_buffer, stride=48)(mixed,mixed,mixed,mixed) r0.y, r0.x, l(44), t0.xxxx
   2: mul_sat r0.y, r0.y, l(3.000000)
   3: add r0.y, r0.y, l(-1.000000)
   4: mul r0.z, r0.y, r0.y
   5: mul r0.y, r0.z, r0.y
   6: mad r0.y, r0.y, l(2.701580), l(1.000000)
   7: mad r0.y, r0.z, l(1.701580), r0.y
   8: ld_structured_indexable(structured_buffer, stride=48)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(16), t0.xyzw
   9: ld_structured_indexable(structured_buffer, stride=48)(mixed,mixed,mixed,mixed) r2.xyzw, r0.x, l(0), t0.xyzw
  10: mul r0.x, r0.y, r1.w
  11: mul r0.yzw, r0.xxxx, v0.xxyz
  12: mov o4.w, r0.x
  13: mul r3.xyz, r0.wyzw, r2.xyzx
  14: mad r3.xyz, r2.zxyz, r0.yzwy, -r3.xyzx
  15: add r3.xyz, r3.xyzx, r3.xyzx
  16: mul r4.xyz, r2.zxyz, r3.xyzx
  17: mad r4.xyz, r2.yzxy, r3.yzxy, -r4.xyzx
  18: mad r0.xyz, r2.wwww, r3.zxyz, r0.yzwy
  19: add r0.xyz, r4.xyzx, r0.xyzx
  20: add r0.xyz, r0.xyzx, r1.xyzx
  21: mul r3.xyzw, r0.yyyy, cb0[63].xyzw
  22: mad r3.xyzw, cb0[62].xyzw, r0.xxxx, r3.xyzw
  23: mad r0.xyzw, cb0[64].xyzw, r0.zzzz, r3.xyzw
  24: add o0.xyzw, r0.xyzw, cb0[65].xyzw
  25: mov o1.xyz, v0.xyzx
  26: mul r0.xyz, r2.xyzx, v1.zxyz
  27: mad r0.xyz, r2.zxyz, v1.xyzx, -r0.xyzx
  28: add r0.xyz, r0.xyzx, r0.xyzx
  29: mul r3.xyz, r0.xyzx, r2.zxyz
  30: mad r3.xyz, r2.yzxy, r0.yzxy, -r3.xyzx
  31: mad r0.xyz, r2.wwww, r0.zxyz, v1.xyzx
  32: add o2.xyz, r3.xyzx, r0.xyzx
  33: mul r0.xyz, r2.xyzx, cb1[1].zxyz
  34: mad r0.xyz, r2.zxyz, cb1[1].xyzx, -r0.xyzx
  35: add r0.xyz, r0.xyzx, r0.xyzx
  36: mul r3.xyz, r0.xyzx, r2.zxyz
  37: mad r3.xyz, r2.yzxy, r0.yzxy, -r3.xyzx
  38: mad r0.xyz, r2.wwww, r0.zxyz, cb1[1].xyzx
  39: add r0.xyz, r3.xyzx, r0.xyzx
  40: add r0.xyz, r0.xyzx, r1.xyzx
  41: mul r1.xyz, r0.yyyy, cb0[51].xyzx
  42: mad r1.xyz, cb0[50].xyzx, r0.xxxx, r1.xyzx
  43: mad r1.xyz, cb0[52].xyzx, r0.zzzz, r1.xyzx
  44: add r0.xyz, -r0.xyzx, cb0[6].xyzx
  45: add o3.xyz, r1.xyzx, cb0[53].xyzx
  46: dp4 r0.w, r2.xyzw, r2.xyzw
  47: mul r1.xyzw, r2.xyzw, l(-1.000000, -1.000000, -1.000000, 1.000000)
  48: div r1.xyzw, r1.xyzw, r0.wwww
  49: mul r2.xyz, r0.zxyz, r1.xyzx
  50: mad r2.xyz, r1.zxyz, r0.xyzx, -r2.xyzx
  51: add r2.xyz, r2.xyzx, r2.xyzx
  52: mad r0.xyz, r1.wwww, r2.zxyz, r0.xyzx
  53: mul r3.xyz, r1.zxyz, r2.xyzx
  54: mad r1.xyz, r1.yzxy, r2.yzxy, -r3.xyzx
  55: add o4.xyz, r0.xyzx, r1.xyzx
  56: ret
