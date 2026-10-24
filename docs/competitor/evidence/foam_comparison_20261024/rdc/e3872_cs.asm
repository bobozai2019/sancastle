Shader hash d3b92d43-33004ac1-7b3826f7-4e6a1024

// Note: shader requires additional functionality:
//       Typed UAV Load Additional Formats
//
cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_uav_typed_texture2d (float,float,float,float) u0
      dcl_uav_typed_texture2d (float,float,float,float) u1
      dcl_input vThreadID.xy
      dcl_temps 3
      dcl_thread_group 32, 32, 1
   0: iadd r0.xyzw, vThreadID.xyxy, l(-1, 0, 1, 0)
   1: ld_uav_typed(texture2d)(float,float,float,float) r1.xyzw, r0.xyyy, u0.xyzw
   2: ld_uav_typed(texture2d)(float,float,float,float) r0.xyzw, r0.zwww, u0.xyzw
   3: add r0.xyzw, r0.xyzw, r1.xyzw
   4: iadd r1.xyzw, vThreadID.xyxy, l(0, -1, 0, 1)
   5: ld_uav_typed(texture2d)(float,float,float,float) r2.xyzw, r1.xyyy, u0.xyzw
   6: ld_uav_typed(texture2d)(float,float,float,float) r1.xyzw, r1.zwww, u0.xyzw
   7: add r0.xyzw, r0.xyzw, r2.xyzw
   8: add r0.xyzw, r1.xyzw, r0.xyzw
   9: mul r0.xyzw, r0.xyzw, l(0.250000, 0.250000, 0.250000, 0.250000)
  10: store_uav_typed u1.xyzw, vThreadID.xyyy, r0.xyzw
  11: ret
