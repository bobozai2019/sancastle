#[compute]
#version 450
// Packed-uint DXBC lowering with explicit recorded arithmetic expression models, not original HLSL.
// Explicit post-swizzle read-stream replay, separate output. Not original alias execution.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
float dx_dp2(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float sum=m0+m1;return sum;}
float dx_dp3(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float m2=a.z*b.z;precise float sum=m0+m1;precise float total=sum+m2;return total;}
layout(set=0,binding=4,std430) readonly buffer ReadStream {uvec4 streamCells[];};
layout(set=0,binding=5,std430) buffer StreamOutput {uvec4 observedStream[];};
void main(){
 uvec4 vThreadID=uvec4(gl_GlobalInvocationID,0u);
 uvec4 r0=uvec4(0u);
 uvec4 r1=uvec4(0u);
 uvec4 r2=uvec4(0u);
 uvec4 r3=uvec4(0u);
 uvec4 r4=uvec4(0u);
 uvec4 r5=uvec4(0u);
 uvec4 r6=uvec4(0u);
 uvec4 r7=uvec4(0u);
 uvec4 r8=uvec4(0u);

 // DXBC 0: iadd r0.xyzw, vThreadID.xyxy, l(0xffffffff, 0x00000000, 0x00000001, 0x00000000)
 uvec4 t0=(vThreadID.xyxy+uvec4(0xffffffffu,0x00000000u,0x00000001u,0x00000000u));
 r0.xyzw=t0.xyzw;
 // DXBC 1: imax r0.x, r0.x, l(0x00000000)
 uvec4 t1=uvec4(max(ivec4(uvec4(r0.x)),ivec4(uvec4(0x00000000u))));
 r0.x=t1.x;
 // DXBC 2: iadd r1.xy, cb0[155].xyxx, l(0xffffffff, 0xffffffff, 0x00000000, 0x00000000)
 uvec4 t2=(constants[155].xyxx+uvec4(0xffffffffu,0xffffffffu,0x00000000u,0x00000000u));
 r1.xy=t2.xy;
 // DXBC 3: imin r0.xyzw, r0.xyzw, r1.xyxy
 uvec4 t3=uvec4(min(ivec4(r0.xyzw),ivec4(r1.xyxy)));
 r0.xyzw=t3.xyzw;
 // DXBC 4: imad r0.x, r0.y, cb0[155].x, r0.x
 uvec4 t4=(uvec4(r0.y)*uvec4(constants[155].x)+uvec4(r0.x));
 r0.x=t4.x;
 // DXBC 5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xy, r0.x, l(0x00000000), u0.xyxx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot5=(vThreadID.y*512u+vThreadID.x)*10u+0u;
 observedStream[streamSlot5]=uvec4((uvec4(r0.x)).x,0u,3u,5u);
 uvec4 t5=streamCells[streamSlot5+1u];
 r0.xy=t5.xy;
 uvec4 streamValue5=uvec4(0u);
 streamValue5.xy=r0.xy;
 observedStream[streamSlot5+1u]=streamValue5;
 // DXBC 6: imad r0.z, r0.w, cb0[155].x, r0.z
 uvec4 t6=(uvec4(r0.w)*uvec4(constants[155].x)+uvec4(r0.z));
 r0.z=t6.z;
 // DXBC 7: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyzw, r0.z, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot7=(vThreadID.y*512u+vThreadID.x)*10u+2u;
 observedStream[streamSlot7]=uvec4((uvec4(r0.z)).x,0u,15u,7u);
 uvec4 t7=streamCells[streamSlot7+1u];
 r2.xyzw=t7.xyzw;
 uvec4 streamValue7=uvec4(0u);
 streamValue7.xyzw=r2.xyzw;
 observedStream[streamSlot7+1u]=streamValue7;
 // DXBC 8: iadd r3.xyzw, vThreadID.xyxy, l(0x00000000, 0xffffffff, 0x00000000, 0x00000001)
 uvec4 t8=(vThreadID.xyxy+uvec4(0x00000000u,0xffffffffu,0x00000000u,0x00000001u));
 r3.xyzw=t8.xyzw;
 // DXBC 9: imax r3.y, r3.y, l(0x00000000)
 uvec4 t9=uvec4(max(ivec4(uvec4(r3.y)),ivec4(uvec4(0x00000000u))));
 r3.y=t9.y;
 // DXBC 10: imin r0.zw, r1.xxxy, r3.zzzw
 uvec4 t10=uvec4(min(ivec4(r1.xxxy),ivec4(r3.zzzw)));
 r0.zw=t10.zw;
 // DXBC 11: imad r0.z, r0.w, cb0[155].x, r0.z
 uvec4 t11=(uvec4(r0.w)*uvec4(constants[155].x)+uvec4(r0.z));
 r0.z=t11.z;
 // DXBC 12: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyzw, r0.z, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot12=(vThreadID.y*512u+vThreadID.x)*10u+4u;
 observedStream[streamSlot12]=uvec4((uvec4(r0.z)).x,0u,15u,12u);
 uvec4 t12=streamCells[streamSlot12+1u];
 r4.xyzw=t12.xyzw;
 uvec4 streamValue12=uvec4(0u);
 streamValue12.xyzw=r4.xyzw;
 observedStream[streamSlot12+1u]=streamValue12;
 // DXBC 13: imin r0.zw, r1.xxxy, r3.xxxy
 uvec4 t13=uvec4(min(ivec4(r1.xxxy),ivec4(r3.xxxy)));
 r0.zw=t13.zw;
 // DXBC 14: ige r1.xy, vThreadID.xyxx, r1.xyxx
 uvec4 t14=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(ivec4(vThreadID.xyxx),ivec4(r1.xyxx)));
 r1.xy=t14.xy;
 // DXBC 15: imad r0.z, r0.w, cb0[155].x, r0.z
 uvec4 t15=(uvec4(r0.w)*uvec4(constants[155].x)+uvec4(r0.z));
 r0.z=t15.z;
 // DXBC 16: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(0x00000000), u0.xxxy
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot16=(vThreadID.y*512u+vThreadID.x)*10u+6u;
 observedStream[streamSlot16]=uvec4((uvec4(r0.z)).x,0u,12u,16u);
 uvec4 t16=streamCells[streamSlot16+1u];
 r0.zw=t16.zw;
 uvec4 streamValue16=uvec4(0u);
 streamValue16.zw=r0.zw;
 observedStream[streamSlot16+1u]=streamValue16;
 // DXBC 17: imad r1.z, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t17=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r1.z=t17.z;
 // DXBC 18: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r1.z, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot18=(vThreadID.y*512u+vThreadID.x)*10u+8u;
 observedStream[streamSlot18]=uvec4((uvec4(r1.z)).x,0u,15u,18u);
 uvec4 t18=streamCells[streamSlot18+1u];
 r3.xyzw=t18.xyzw;
 uvec4 streamValue18=uvec4(0u);
 streamValue18.xyzw=r3.xyzw;
 observedStream[streamSlot18+1u]=streamValue18;
 // DXBC 19: ushr r5.xy, r0.zwzz, l(0x00000010, 0x00000008, 0x00000000, 0x00000000)
 uvec4 t19=(r0.zwzz>>(uvec4(0x00000010u,0x00000008u,0x00000000u,0x00000000u)&uvec4(31u)));
 r5.xy=t19.xy;
 // DXBC 20: bfi r0.z, l(0x00000010), l(0x00000010), r0.w, r5.x
 uvec4 t20=uvec4(bitfieldInsert((uvec4(r5.x)).x,(uvec4(r0.w)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r5.x)).y,(uvec4(r0.w)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r5.x)).z,(uvec4(r0.w)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r5.x)).w,(uvec4(r0.w)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.z=t20.z;
 // DXBC 21: utof r0.w, r5.y
 precise vec4 f21=vec4(uvec4(r5.y));
 uvec4 t21=floatBitsToUint(f21);
 r0.w=t21.w;
 // DXBC 22: mad r5.y, r0.w, l(0x35000001), l(0xc0800000)
 precise vec4 f22=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t22=floatBitsToUint(f22);
 r5.y=t22.y;
 // DXBC 23: and r0.z, r0.z, l(0x00ffffff)
 uvec4 t23=(uvec4(r0.z)&uvec4(0x00ffffffu));
 r0.z=t23.z;
 // DXBC 24: utof r0.z, r0.z
 precise vec4 f24=vec4(uvec4(r0.z));
 uvec4 t24=floatBitsToUint(f24);
 r0.z=t24.z;
 // DXBC 25: mad r5.x, r0.z, l(0x35000001), l(0xc0800000)
 precise vec4 f25=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t25=floatBitsToUint(f25);
 r5.x=t25.x;
 // DXBC 26: ushr r0.xz, r0.xxyx, l(0x00000010, 0x00000000, 0x00000008, 0x00000000)
 uvec4 t26=(r0.xxyx>>(uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)&uvec4(31u)));
 r0.xz=t26.xz;
 // DXBC 27: bfi r0.x, l(0x00000010), l(0x00000010), r0.y, r0.x
 uvec4 t27=uvec4(bitfieldInsert((uvec4(r0.x)).x,(uvec4(r0.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.x)).y,(uvec4(r0.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.x)).z,(uvec4(r0.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.x)).w,(uvec4(r0.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.x=t27.x;
 // DXBC 28: utof r0.y, r0.z
 precise vec4 f28=vec4(uvec4(r0.z));
 uvec4 t28=floatBitsToUint(f28);
 r0.y=t28.y;
 // DXBC 29: mad r6.y, r0.y, l(0x35000001), l(0xc0800000)
 precise vec4 f29=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t29=floatBitsToUint(f29);
 r6.y=t29.y;
 // DXBC 30: and r0.x, r0.x, l(0x00ffffff)
 uvec4 t30=(uvec4(r0.x)&uvec4(0x00ffffffu));
 r0.x=t30.x;
 // DXBC 31: utof r0.x, r0.x
 precise vec4 f31=vec4(uvec4(r0.x));
 uvec4 t31=floatBitsToUint(f31);
 r0.x=t31.x;
 // DXBC 32: mad r6.x, r0.x, l(0x35000001), l(0xc0800000)
 precise vec4 f32=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t32=floatBitsToUint(f32);
 r6.x=t32.x;
 // DXBC 33: ushr r0.xyz, r2.xyzx, l(0x00000010, 0x00000008, 0x00000018, 0x00000000)
 uvec4 t33=(r2.xyzx>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x00000000u)&uvec4(31u)));
 r0.xyz=t33.xyz;
 // DXBC 34: bfi r0.xz, l(0x00000010, 0x00000000, 0x00000018, 0x00000000), l(0x00000010, 0x00000000, 0x00000008, 0x00000000), r2.yywy, r0.xxzx
 uvec4 t34=uvec4(bitfieldInsert((r0.xxzx).x,(r2.yywy).x,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r0.xxzx).y,(r2.yywy).y,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r0.xxzx).z,(r2.yywy).z,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r0.xxzx).w,(r2.yywy).w,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).w)));
 r0.xz=t34.xz;
 // DXBC 35: utof r0.y, r0.y
 precise vec4 f35=vec4(uvec4(r0.y));
 uvec4 t35=floatBitsToUint(f35);
 r0.y=t35.y;
 // DXBC 36: mad r7.y, r0.y, l(0x35000001), l(0xc0800000)
 precise vec4 f36=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t36=floatBitsToUint(f36);
 r7.y=t36.y;
 // DXBC 37: and r0.y, r2.z, l(0x00ffffff)
 uvec4 t37=(uvec4(r2.z)&uvec4(0x00ffffffu));
 r0.y=t37.y;
 // DXBC 38: utof r0.y, r0.y
 precise vec4 f38=vec4(uvec4(r0.y));
 uvec4 t38=floatBitsToUint(f38);
 r0.y=t38.y;
 // DXBC 39: mul r7.z, r0.y, l(0x3521999b)
 precise vec4 f39=(uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t39=floatBitsToUint(f39);
 r7.z=t39.z;
 // DXBC 40: and r0.xy, r0.xzxx, l(0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000)
 uvec4 t40=(r0.xzxx&uvec4(0x00ffffffu,0x00ffffffu,0x00000000u,0x00000000u));
 r0.xy=t40.xy;
 // DXBC 41: utof r0.xy, r0.xyxx
 precise vec4 f41=vec4(r0.xyxx);
 uvec4 t41=floatBitsToUint(f41);
 r0.xy=t41.xy;
 // DXBC 42: mad r7.xw, r0.xxxy, l(0x35000001, 0x00000000, 0x00000000, 0x3521999b), l(0xc0800000, 0x00000000, 0x00000000, 0x00000000)
 precise vec4 f42=fma(uintBitsToFloat(r0.xxxy),uintBitsToFloat(uvec4(0x35000001u,0x00000000u,0x00000000u,0x3521999bu)),uintBitsToFloat(uvec4(0xc0800000u,0x00000000u,0x00000000u,0x00000000u)));
 uvec4 t42=floatBitsToUint(f42);
 r7.xw=t42.xw;
 // DXBC 43: mov r0.z, l(0x00000000)
 uvec4 t43=uvec4(0x00000000u);
 r0.z=t43.z;
 // DXBC 44: ushr r2.xyzw, r3.xyzw, l(0x00000010, 0x00000008, 0x00000018, 0x0000001c)
 uvec4 t44=(r3.xyzw>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x0000001cu)&uvec4(31u)));
 r2.xyzw=t44.xyzw;
 // DXBC 45: bfi r2.xz, l(0x00000010, 0x00000000, 0x00000018, 0x00000000), l(0x00000010, 0x00000000, 0x00000008, 0x00000000), r3.yywy, r2.xxzx
 uvec4 t45=uvec4(bitfieldInsert((r2.xxzx).x,(r3.yywy).x,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r2.xxzx).y,(r3.yywy).y,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r2.xxzx).z,(r3.yywy).z,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r2.xxzx).w,(r3.yywy).w,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).w)));
 r2.xz=t45.xz;
 // DXBC 46: and r2.xz, r2.xxzx, l(0x00ffffff, 0x00000000, 0x00ffffff, 0x00000000)
 uvec4 t46=(r2.xxzx&uvec4(0x00ffffffu,0x00000000u,0x00ffffffu,0x00000000u));
 r2.xz=t46.xz;
 // DXBC 47: utof r2.xyzw, r2.xyzw
 precise vec4 f47=vec4(r2.xyzw);
 uvec4 t47=floatBitsToUint(f47);
 r2.xyzw=t47.xyzw;
 // DXBC 48: mul r0.w, r2.z, l(0x3521999b)
 precise vec4 f48=(uintBitsToFloat(uvec4(r2.z))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t48=floatBitsToUint(f48);
 r0.w=t48.w;
 // DXBC 49: and r3.yz, r3.zzxz, l(0x00000000, 0x00ffffff, 0x000000ff, 0x00000000)
 uvec4 t49=(r3.zzxz&uvec4(0x00000000u,0x00ffffffu,0x000000ffu,0x00000000u));
 r3.yz=t49.yz;
 // DXBC 50: ubfe r8.xyz, l(0x00000008, 0x00000008, 0x00000004, 0x00000000), l(0x00000008, 0x00000010, 0x00000018, 0x00000000), r3.xwwx
 uvec4 t50=uvec4(bitfieldExtract((r3.xwwx).x,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).x),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).x)),bitfieldExtract((r3.xwwx).y,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).y),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).y)),bitfieldExtract((r3.xwwx).z,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).z),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).z)),bitfieldExtract((r3.xwwx).w,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).w),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).w)));
 r8.xyz=t50.xyz;
 // DXBC 51: utof r8.xyz, r8.xyzx
 precise vec4 f51=vec4(r8.xyzx);
 uvec4 t51=floatBitsToUint(f51);
 r8.xyz=t51.xyz;
 // DXBC 52: utof r3.xy, r3.yzyy
 precise vec4 f52=vec4(r3.yzyy);
 uvec4 t52=floatBitsToUint(f52);
 r3.xy=t52.xy;
 // DXBC 53: mul r0.x, r3.x, l(0x3521999b)
 precise vec4 f53=(uintBitsToFloat(uvec4(r3.x))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t53=floatBitsToUint(f53);
 r0.x=t53.x;
 // DXBC 54: movc r7.xyzw, r1.xxxx, r0.zzxw, r7.xyzw
 uvec4 t54=mix(r7.xyzw,r0.zzxw,notEqual(r1.xxxx,uvec4(0u)));
 r7.xyzw=t54.xyzw;
 // DXBC 55: add r1.xw, r6.xxxy, r7.xxxy
 precise vec4 f55=(uintBitsToFloat(r6.xxxy)+uintBitsToFloat(r7.xxxy));
 uvec4 t55=floatBitsToUint(f55);
 r1.xw=t55.xw;
 // DXBC 56: add r1.xw, r5.xxxy, r1.xxxw
 precise vec4 f56=(uintBitsToFloat(r5.xxxy)+uintBitsToFloat(r1.xxxw));
 uvec4 t56=floatBitsToUint(f56);
 r1.xw=t56.xw;
 // DXBC 57: ushr r5.xyz, r4.xyzx, l(0x00000010, 0x00000008, 0x00000018, 0x00000000)
 uvec4 t57=(r4.xyzx>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x00000000u)&uvec4(31u)));
 r5.xyz=t57.xyz;
 // DXBC 58: bfi r3.zw, l(0x00000000, 0x00000000, 0x00000010, 0x00000018), l(0x00000000, 0x00000000, 0x00000010, 0x00000008), r4.yyyw, r5.xxxz
 uvec4 t58=uvec4(bitfieldInsert((r5.xxxz).x,(r4.yyyw).x,int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)).x),int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000018u)).x)),bitfieldInsert((r5.xxxz).y,(r4.yyyw).y,int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)).y),int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000018u)).y)),bitfieldInsert((r5.xxxz).z,(r4.yyyw).z,int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)).z),int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000018u)).z)),bitfieldInsert((r5.xxxz).w,(r4.yyyw).w,int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)).w),int((uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000018u)).w)));
 r3.zw=t58.zw;
 // DXBC 59: utof r0.y, r5.y
 precise vec4 f59=vec4(uvec4(r5.y));
 uvec4 t59=floatBitsToUint(f59);
 r0.y=t59.y;
 // DXBC 60: mad r5.y, r0.y, l(0x35000001), l(0xc0800000)
 precise vec4 f60=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t60=floatBitsToUint(f60);
 r5.y=t60.y;
 // DXBC 61: and r0.y, r4.z, l(0x00ffffff)
 uvec4 t61=(uvec4(r4.z)&uvec4(0x00ffffffu));
 r0.y=t61.y;
 // DXBC 62: utof r0.y, r0.y
 precise vec4 f62=vec4(uvec4(r0.y));
 uvec4 t62=floatBitsToUint(f62);
 r0.y=t62.y;
 // DXBC 63: mul r5.z, r0.y, l(0x3521999b)
 precise vec4 f63=(uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t63=floatBitsToUint(f63);
 r5.z=t63.z;
 // DXBC 64: and r3.zw, r3.zzzw, l(0x00000000, 0x00000000, 0x00ffffff, 0x00ffffff)
 uvec4 t64=(r3.zzzw&uvec4(0x00000000u,0x00000000u,0x00ffffffu,0x00ffffffu));
 r3.zw=t64.zw;
 // DXBC 65: utof r3.zw, r3.zzzw
 precise vec4 f65=vec4(r3.zzzw);
 uvec4 t65=floatBitsToUint(f65);
 r3.zw=t65.zw;
 // DXBC 66: mad r5.xw, r3.zzzw, l(0x35000001, 0x00000000, 0x00000000, 0x3521999b), l(0xc0800000, 0x00000000, 0x00000000, 0x00000000)
 precise vec4 f66=fma(uintBitsToFloat(r3.zzzw),uintBitsToFloat(uvec4(0x35000001u,0x00000000u,0x00000000u,0x3521999bu)),uintBitsToFloat(uvec4(0xc0800000u,0x00000000u,0x00000000u,0x00000000u)));
 uvec4 t66=floatBitsToUint(f66);
 r5.xw=t66.xw;
 // DXBC 67: movc r4.xyzw, r1.yyyy, r0.zzxw, r5.xyzw
 uvec4 t67=mix(r5.xyzw,r0.zzxw,notEqual(r1.yyyy,uvec4(0u)));
 r4.xyzw=t67.xyzw;
 // DXBC 68: add r0.xy, r1.xwxx, r4.xyxx
 precise vec4 f68=(uintBitsToFloat(r1.xwxx)+uintBitsToFloat(r4.xyxx));
 uvec4 t68=floatBitsToUint(f68);
 r0.xy=t68.xy;
 // DXBC 69: itof r1.xy, vThreadID.xyxx
 precise vec4 f69=vec4(ivec4(vThreadID.xyxx));
 uvec4 t69=floatBitsToUint(f69);
 r1.xy=t69.xy;
 // DXBC 70: add r1.xy, r1.xyxx, l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f70=(uintBitsToFloat(r1.xyxx)+uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t70=floatBitsToUint(f70);
 r1.xy=t70.xy;
 // DXBC 71: itof r3.zw, cb0[155].xxxy
 precise vec4 f71=vec4(ivec4(constants[155].xxxy));
 uvec4 t71=floatBitsToUint(f71);
 r3.zw=t71.zw;
 // DXBC 72: div_sat r1.xy, r1.xyxx, r3.zwzz
 precise vec4 f72=clamp((uintBitsToFloat(r1.xyxx)/uintBitsToFloat(r3.zwzz)),vec4(0),vec4(1));
 uvec4 t72=floatBitsToUint(f72);
 r1.xy=t72.xy;
 // DXBC 73: add r3.zw, -r1.xxxy, l(0x00000000, 0x00000000, 0x3f800000, 0x3f800000)
 precise vec4 f73=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(r1.xxxy)))+uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f800000u,0x3f800000u)));
 uvec4 t73=floatBitsToUint(f73);
 r3.zw=t73.zw;
 // DXBC 74: mul r1.xy, r1.xyxx, l(0x41a00000, 0x41a00000, 0x00000000, 0x00000000)
 precise vec4 f74=(uintBitsToFloat(r1.xyxx)*uintBitsToFloat(uvec4(0x41a00000u,0x41a00000u,0x00000000u,0x00000000u)));
 uvec4 t74=floatBitsToUint(f74);
 r1.xy=t74.xy;
 // DXBC 75: min r1.xy, r1.xyxx, l(0x3f800000, 0x3f800000, 0x00000000, 0x00000000)
 precise vec4 f75=min(uintBitsToFloat(r1.xyxx),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x00000000u,0x00000000u)));
 uvec4 t75=floatBitsToUint(f75);
 r1.xy=t75.xy;
 // DXBC 76: mul r3.zw, r3.zzzw, l(0x00000000, 0x00000000, 0x41a00000, 0x41a00000)
 precise vec4 f76=(uintBitsToFloat(r3.zzzw)*uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x41a00000u,0x41a00000u)));
 uvec4 t76=floatBitsToUint(f76);
 r3.zw=t76.zw;
 // DXBC 77: min r3.zw, r3.zzzw, l(0x00000000, 0x00000000, 0x3f800000, 0x3f800000)
 precise vec4 f77=min(uintBitsToFloat(r3.zzzw),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f800000u,0x3f800000u)));
 uvec4 t77=floatBitsToUint(f77);
 r3.zw=t77.zw;
 // DXBC 78: mad r4.xy, r3.zwzz, l(0xc0000000, 0xc0000000, 0x00000000, 0x00000000), l(0x40400000, 0x40400000, 0x00000000, 0x00000000)
 precise vec4 f78=fma(uintBitsToFloat(r3.zwzz),uintBitsToFloat(uvec4(0xc0000000u,0xc0000000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x40400000u,0x40400000u,0x00000000u,0x00000000u)));
 uvec4 t78=floatBitsToUint(f78);
 r4.xy=t78.xy;
 // DXBC 79: mul r3.zw, r3.zzzw, r3.zzzw
 precise vec4 f79=(uintBitsToFloat(r3.zzzw)*uintBitsToFloat(r3.zzzw));
 uvec4 t79=floatBitsToUint(f79);
 r3.zw=t79.zw;
 // DXBC 80: mul r3.zw, r3.zzzw, r4.xxxy
 precise vec4 f80=(uintBitsToFloat(r3.zzzw)*uintBitsToFloat(r4.xxxy));
 uvec4 t80=floatBitsToUint(f80);
 r3.zw=t80.zw;
 // DXBC 81: mad r4.xy, r1.xyxx, l(0xc0000000, 0xc0000000, 0x00000000, 0x00000000), l(0x40400000, 0x40400000, 0x00000000, 0x00000000)
 precise vec4 f81=fma(uintBitsToFloat(r1.xyxx),uintBitsToFloat(uvec4(0xc0000000u,0xc0000000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x40400000u,0x40400000u,0x00000000u,0x00000000u)));
 uvec4 t81=floatBitsToUint(f81);
 r4.xy=t81.xy;
 // DXBC 82: mul r1.xy, r1.xyxx, r1.xyxx
 precise vec4 f82=(uintBitsToFloat(r1.xyxx)*uintBitsToFloat(r1.xyxx));
 uvec4 t82=floatBitsToUint(f82);
 r1.xy=t82.xy;
 // DXBC 83: mul r1.xy, r1.xyxx, r4.xyxx
 precise vec4 f83=(uintBitsToFloat(r1.xyxx)*uintBitsToFloat(r4.xyxx));
 uvec4 t83=floatBitsToUint(f83);
 r1.xy=t83.xy;
 // DXBC 84: mul r0.z, r3.z, r1.x
 precise vec4 f84=(uintBitsToFloat(uvec4(r3.z))*uintBitsToFloat(uvec4(r1.x)));
 uvec4 t84=floatBitsToUint(f84);
 r0.z=t84.z;
 // DXBC 85: mul r0.z, r1.y, r0.z
 precise vec4 f85=(uintBitsToFloat(uvec4(r1.y))*uintBitsToFloat(uvec4(r0.z)));
 uvec4 t85=floatBitsToUint(f85);
 r0.z=t85.z;
 // DXBC 86: mad r0.z, -r0.z, r3.w, l(0x3f800000)
 precise vec4 f86=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.z)))),uintBitsToFloat(uvec4(r3.w)),uintBitsToFloat(uvec4(0x3f800000u)));
 uvec4 t86=floatBitsToUint(f86);
 r0.z=t86.z;
 // DXBC 87: add r1.x, r7.z, l(0xbd4ccccd)
 precise vec4 f87=(uintBitsToFloat(uvec4(r7.z))+uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t87=floatBitsToUint(f87);
 r1.x=t87.x;
 // DXBC 88: max r1.x, r1.x, l(0x00000000)
 precise vec4 f88=max(uintBitsToFloat(uvec4(r1.x)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t88=floatBitsToUint(f88);
 r1.x=t88.x;
 // DXBC 89: add r1.y, r1.x, r7.w
 precise vec4 f89=(uintBitsToFloat(uvec4(r1.x))+uintBitsToFloat(uvec4(r7.w)));
 uvec4 t89=floatBitsToUint(f89);
 r1.y=t89.y;
 // DXBC 90: mad r3.yz, r3.xxyx, l(0x00000000, 0x3521999b, 0x3f800000, 0x00000000), l(0x00000000, 0xbd4ccccd, 0x3f000000, 0x00000000)
 precise vec4 f90=fma(uintBitsToFloat(r3.xxyx),uintBitsToFloat(uvec4(0x00000000u,0x3521999bu,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0x00000000u,0xbd4ccccdu,0x3f000000u,0x00000000u)));
 uvec4 t90=floatBitsToUint(f90);
 r3.yz=t90.yz;
 // DXBC 91: add r1.w, r3.x, l(0x3f000000)
 precise vec4 f91=(uintBitsToFloat(uvec4(r3.x))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t91=floatBitsToUint(f91);
 r1.w=t91.w;
 // DXBC 92: ftou r4.x, r1.w
 uvec4 t92=uvec4(uintBitsToFloat(uvec4(r1.w)));
 r4.x=t92.x;
 // DXBC 93: max r1.w, r3.y, l(0x00000000)
 precise vec4 f93=max(uintBitsToFloat(uvec4(r3.y)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t93=floatBitsToUint(f93);
 r1.w=t93.w;
 // DXBC 94: ftou r3.x, r3.z
 uvec4 t94=uvec4(uintBitsToFloat(uvec4(r3.z)));
 r3.x=t94.x;
 // DXBC 95: mad r3.y, r2.z, l(0x3521999b), r1.w
 precise vec4 f95=fma(uintBitsToFloat(uvec4(r2.z)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r1.w)));
 uvec4 t95=floatBitsToUint(f95);
 r3.y=t95.y;
 // DXBC 96: add r5.x, r1.y, -r3.y
 precise vec4 f96=(uintBitsToFloat(uvec4(r1.y))+uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r3.y)))));
 uvec4 t96=floatBitsToUint(f96);
 r5.x=t96.x;
 // DXBC 97: lt r1.y, r1.y, r0.w
 uvec4 t97=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(r0.w))));
 r1.y=t97.y;
 // DXBC 98: add r3.z, r4.z, l(0xbd4ccccd)
 precise vec4 f98=(uintBitsToFloat(uvec4(r4.z))+uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t98=floatBitsToUint(f98);
 r3.z=t98.z;
 // DXBC 99: max r3.z, r3.z, l(0x00000000)
 precise vec4 f99=max(uintBitsToFloat(uvec4(r3.z)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t99=floatBitsToUint(f99);
 r3.z=t99.z;
 // DXBC 100: add r3.w, r3.z, r4.w
 precise vec4 f100=(uintBitsToFloat(uvec4(r3.z))+uintBitsToFloat(uvec4(r4.w)));
 uvec4 t100=floatBitsToUint(f100);
 r3.w=t100.w;
 // DXBC 101: lt r4.z, r3.y, r4.w
 uvec4 t101=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r3.y)),uintBitsToFloat(uvec4(r4.w))));
 r4.z=t101.z;
 // DXBC 102: add r5.y, -r3.y, r3.w
 precise vec4 f102=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r3.y))))+uintBitsToFloat(uvec4(r3.w)));
 uvec4 t102=floatBitsToUint(f102);
 r5.y=t102.y;
 // DXBC 103: lt r0.w, r3.w, r0.w
 uvec4 t103=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r3.w)),uintBitsToFloat(uvec4(r0.w))));
 r0.w=t103.w;
 // DXBC 104: lt r3.y, r3.y, r7.w
 uvec4 t104=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r3.y)),uintBitsToFloat(uvec4(r7.w))));
 r3.y=t104.y;
 // DXBC 105: mul r5.xy, r5.xyxx, cb0[154].zwzz
 precise vec4 f105=(uintBitsToFloat(r5.xyxx)*uintBitsToFloat(constants[154].zwzz));
 uvec4 t105=floatBitsToUint(f105);
 r5.xy=t105.xy;
 // DXBC 106: mul r5.xy, r5.xyxx, -cb0[157].wwww
 precise vec4 f106=(uintBitsToFloat(r5.xyxx)*uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(constants[157].wwww))));
 uvec4 t106=floatBitsToUint(f106);
 r5.xy=t106.xy;
 // DXBC 107: mad r6.y, r2.y, l(0x35000001), l(0xc0800000)
 precise vec4 f107=fma(uintBitsToFloat(uvec4(r2.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t107=floatBitsToUint(f107);
 r6.y=t107.y;
 // DXBC 108: add r2.y, r2.w, l(0x3f000000)
 precise vec4 f108=(uintBitsToFloat(uvec4(r2.w))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t108=floatBitsToUint(f108);
 r2.y=t108.y;
 // DXBC 109: ftou r2.y, r2.y
 uvec4 t109=uvec4(uintBitsToFloat(uvec4(r2.y)));
 r2.y=t109.y;
 // DXBC 110: ishl r7.w, r2.y, l(0x0000001c)
 uvec4 t110=(uvec4(r2.y)<<(uvec4(0x0000001cu)&uvec4(31u)));
 r7.w=t110.w;
 // DXBC 111: mad r6.x, r2.x, l(0x35000001), l(0xc0800000)
 precise vec4 f111=fma(uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t111=floatBitsToUint(f111);
 r6.x=t111.x;
 // DXBC 112: add r2.x, r2.z, l(0x3f000000)
 precise vec4 f112=(uintBitsToFloat(uvec4(r2.z))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t112=floatBitsToUint(f112);
 r2.x=t112.x;
 // DXBC 113: ftou r2.x, r2.x
 uvec4 t113=uvec4(uintBitsToFloat(uvec4(r2.x)));
 r2.x=t113.x;
 // DXBC 114: mad r2.yz, r5.xxyx, cb0[157].zzzz, r6.xxyx
 precise vec4 f114=fma(uintBitsToFloat(r5.xxyx),uintBitsToFloat(constants[157].zzzz),uintBitsToFloat(r6.xxyx));
 uvec4 t114=floatBitsToUint(f114);
 r2.yz=t114.yz;
 // DXBC 115: mul r5.xy, r2.yzyy, cb0[159].yyyy
 precise vec4 f115=(uintBitsToFloat(r2.yzyy)*uintBitsToFloat(constants[159].yyyy));
 uvec4 t115=floatBitsToUint(f115);
 r5.xy=t115.xy;
 // DXBC 116: mad r2.yz, -r5.xxyx, cb0[157].zzzz, r2.yyzy
 precise vec4 f116=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(r5.xxyx))),uintBitsToFloat(constants[157].zzzz),uintBitsToFloat(r2.yyzy));
 uvec4 t116=floatBitsToUint(f116);
 r2.yz=t116.yz;
 // DXBC 117: mul r5.xy, r0.zzzz, r2.yzyy
 precise vec4 f117=(uintBitsToFloat(r0.zzzz)*uintBitsToFloat(r2.yzyy));
 uvec4 t117=floatBitsToUint(f117);
 r5.xy=t117.xy;
 // DXBC 118: mad r2.yz, -r5.xxyx, cb0[157].zzzz, r2.yyzy
 precise vec4 foldedDepthDt=uintBitsToFloat(r0).zzzz*uintBitsToFloat(constants[157]).zzzz;
 precise vec4 f118=fma(uintBitsToFloat(r2.yyzy),-foldedDepthDt,uintBitsToFloat(r2.yyzy));
 uvec4 t118=floatBitsToUint(f118);
 r2.yz=t118.yz;
 // DXBC 119: mad r0.xy, r2.yzyy, cb0[159].wwww, r0.xyxx
 precise vec4 f119=fma(uintBitsToFloat(r2.yzyy),uintBitsToFloat(constants[159].wwww),uintBitsToFloat(r0.xyxx));
 uvec4 t119=floatBitsToUint(f119);
 r0.xy=t119.xy;
 // DXBC 120: add r0.z, cb0[159].w, l(0x40800000)
 precise vec4 f120=(uintBitsToFloat(uvec4(constants[159].w))+uintBitsToFloat(uvec4(0x40800000u)));
 uvec4 t120=floatBitsToUint(f120);
 r0.z=t120.z;
 // DXBC 121: div r0.xy, r0.xyxx, r0.zzzz
 precise vec4 f121=(uintBitsToFloat(r0.xyxx)/uintBitsToFloat(r0.zzzz));
 uvec4 t121=floatBitsToUint(f121);
 r0.xy=t121.xy;
 // DXBC 122: mul r0.z, cb0[154].x, l(0x38d1b717)
 precise vec4 f122=(uintBitsToFloat(uvec4(constants[154].x))*uintBitsToFloat(uvec4(0x38d1b717u)));
 uvec4 t122=floatBitsToUint(f122);
 r0.z=t122.z;
 // DXBC 123: ge r1.xw, r0.zzzz, r1.xxxw
 uvec4 t123=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(r0.zzzz),uintBitsToFloat(r1.xxxw)));
 r1.xw=t123.xw;
 // DXBC 124: and r1.x, r3.y, r1.x
 uvec4 t124=(uvec4(r3.y)&uvec4(r1.x));
 r1.x=t124.x;
 // DXBC 125: ge r0.z, r0.z, r3.z
 uvec4 t125=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(r3.z))));
 r0.z=t125.z;
 // DXBC 126: and r0.z, r4.z, r0.z
 uvec4 t126=(uvec4(r4.z)&uvec4(r0.z));
 r0.z=t126.z;
 // DXBC 127: and r1.y, r1.y, r1.w
 uvec4 t127=(uvec4(r1.y)&uvec4(r1.w));
 r1.y=t127.y;
 // DXBC 128: and r0.w, r0.w, r1.w
 uvec4 t128=(uvec4(r0.w)&uvec4(r1.w));
 r0.w=t128.w;
 // DXBC 129: or r0.z, r0.z, r0.w
 uvec4 t129=(uvec4(r0.z)|uvec4(r0.w));
 r0.z=t129.z;
 // DXBC 130: movc r5.y, r0.z, l(0x00000000), r0.y
 uvec4 t130=mix(uvec4(r0.y),uvec4(0x00000000u),notEqual(uvec4(r0.z),uvec4(0u)));
 r5.y=t130.y;
 // DXBC 131: or r0.y, r1.x, r1.y
 uvec4 t131=(uvec4(r1.x)|uvec4(r1.y));
 r0.y=t131.y;
 // DXBC 132: movc r5.x, r0.y, l(0x00000000), r0.x
 uvec4 t132=mix(uvec4(r0.x),uvec4(0x00000000u),notEqual(uvec4(r0.y),uvec4(0u)));
 r5.x=t132.x;
 // DXBC 133: mul r0.xy, r5.xyxx, cb0[158].xxxx
 precise vec4 f133=(uintBitsToFloat(r5.xyxx)*uintBitsToFloat(constants[158].xxxx));
 uvec4 t133=floatBitsToUint(f133);
 r0.xy=t133.xy;
 // DXBC 134: dp2 r0.z, r5.xyxx, r5.xyxx
 precise float dot134m0=(uintBitsToFloat(r5.xyxx)).x*(uintBitsToFloat(r5.xyxx)).x;
 precise vec4 f134=vec4(fma((uintBitsToFloat(r5.xyxx)).y,(uintBitsToFloat(r5.xyxx)).y,dot134m0));
 uvec4 t134=floatBitsToUint(f134);
 r0.z=t134.z;
 // DXBC 135: rsq r0.w, r0.z
 precise vec4 f135=inversesqrt(uintBitsToFloat(uvec4(r0.z)));
 uvec4 t135=floatBitsToUint(f135);
 r0.w=t135.w;
 // DXBC 136: mul r0.xy, r0.wwww, r0.xyxx
 precise vec4 f136=(uintBitsToFloat(r0.wwww)*uintBitsToFloat(r0.xyxx));
 uvec4 t136=floatBitsToUint(f136);
 r0.xy=t136.xy;
 // DXBC 137: mul r0.w, cb0[158].x, cb0[158].x
 precise vec4 f137=(uintBitsToFloat(uvec4(constants[158].x))*uintBitsToFloat(uvec4(constants[158].x)));
 uvec4 t137=floatBitsToUint(f137);
 r0.w=t137.w;
 // DXBC 138: lt r0.z, r0.w, r0.z
 uvec4 t138=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r0.z))));
 r0.z=t138.z;
 // DXBC 139: movc r0.xy, r0.zzzz, r0.xyxx, r5.xyxx
 uvec4 t139=mix(r5.xyxx,r0.xyxx,notEqual(r0.zzzz,uvec4(0u)));
 r0.xy=t139.xy;
 // DXBC 140: add r0.xy, r0.xyxx, l(0x40800000, 0x40800000, 0x00000000, 0x00000000)
 precise vec4 f140=(uintBitsToFloat(r0.xyxx)+uintBitsToFloat(uvec4(0x40800000u,0x40800000u,0x00000000u,0x00000000u)));
 uvec4 t140=floatBitsToUint(f140);
 r0.xy=t140.xy;
 // DXBC 141: mul_sat r0.xy, r0.xyxx, l(0x3e000000, 0x3e000000, 0x00000000, 0x00000000)
 precise vec4 f141=clamp((uintBitsToFloat(r0.xyxx)*uintBitsToFloat(uvec4(0x3e000000u,0x3e000000u,0x00000000u,0x00000000u))),vec4(0),vec4(1));
 uvec4 t141=floatBitsToUint(f141);
 r0.xy=t141.xy;
 // DXBC 142: mad r0.xy, r0.xyxx, l(0x4b7fffff, 0x4b7fffff, 0x00000000, 0x00000000), l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f142=fma(uintBitsToFloat(r0.xyxx),uintBitsToFloat(uvec4(0x4b7fffffu,0x4b7fffffu,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t142=floatBitsToUint(f142);
 r0.xy=t142.xy;
 // DXBC 143: mad r0.z, r8.x, l(0x3f800000), l(0x3f000000)
 precise vec4 f143=fma(uintBitsToFloat(uvec4(r8.x)),uintBitsToFloat(uvec4(0x3f800000u)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t143=floatBitsToUint(f143);
 r0.z=t143.z;
 // DXBC 144: add r1.xy, r8.yzyy, l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f144=(uintBitsToFloat(r8.yzyy)+uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t144=floatBitsToUint(f144);
 r1.xy=t144.xy;
 // DXBC 145: ftou r1.xy, r1.xyxx
 uvec4 t145=uvec4(uintBitsToFloat(r1.xyxx));
 r1.xy=t145.xy;
 // DXBC 146: ftou r0.xyz, r0.xyzx
 uvec4 t146=uvec4(uintBitsToFloat(r0.xyzx));
 r0.xyz=t146.xyz;
 // DXBC 147: imad r0.z, r0.z, l(0x00000100), r3.x
 uvec4 t147=(uvec4(r0.z)*uvec4(0x00000100u)+uvec4(r3.x));
 r0.z=t147.z;
 // DXBC 148: bfi r3.x, l(0x00000010), l(0x00000010), r0.x, r0.z
 uvec4 t148=uvec4(bitfieldInsert((uvec4(r0.z)).x,(uvec4(r0.x)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.z)).y,(uvec4(r0.x)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.z)).z,(uvec4(r0.x)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.z)).w,(uvec4(r0.x)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r3.x=t148.x;
 // DXBC 149: ushr r0.x, r0.x, l(0x00000010)
 uvec4 t149=(uvec4(r0.x)>>(uvec4(0x00000010u)&uvec4(31u)));
 r0.x=t149.x;
 // DXBC 150: ishl r0.y, r0.y, l(0x00000008)
 uvec4 t150=(uvec4(r0.y)<<(uvec4(0x00000008u)&uvec4(31u)));
 r0.y=t150.y;
 // DXBC 151: or r3.y, r0.y, r0.x
 uvec4 t151=(uvec4(r0.y)|uvec4(r0.x));
 r3.y=t151.y;
 // DXBC 152: ishl r0.x, r2.x, l(0x00000018)
 uvec4 t152=(uvec4(r2.x)<<(uvec4(0x00000018u)&uvec4(31u)));
 r0.x=t152.x;
 // DXBC 153: ushr r0.y, r2.x, l(0x00000008)
 uvec4 t153=(uvec4(r2.x)>>(uvec4(0x00000008u)&uvec4(31u)));
 r0.y=t153.y;
 // DXBC 154: mov r4.y, l(0x00000000)
 uvec4 t154=uvec4(0x00000000u);
 r4.y=t154.y;
 // DXBC 155: iadd r0.xy, r0.xyxx, r4.xyxx
 uvec4 t155=(r0.xyxx+r4.xyxx);
 r0.xy=t155.xy;
 // DXBC 156: imad r0.y, r1.x, l(0x00010000), r0.y
 uvec4 t156=(uvec4(r1.x)*uvec4(0x00010000u)+uvec4(r0.y));
 r0.y=t156.y;
 // DXBC 157: mov r3.z, r0.x
 uvec4 t157=uvec4(r0.x);
 r3.z=t157.z;
 // DXBC 158: imad r3.w, r1.y, l(0x01000000), r0.y
 uvec4 t158=(uvec4(r1.y)*uvec4(0x01000000u)+uvec4(r0.y));
 r3.w=t158.w;
 // DXBC 159: mov r7.xyz, l(0x00000000,0x00000000,0x00000000,0x00000000)
 uvec4 t159=uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u);
 r7.xyz=t159.xyz;
 // DXBC 160: iadd r0.xyzw, r7.xyzw, r3.xyzw
 uvec4 t160=(r7.xyzw+r3.xyzw);
 r0.xyzw=t160.xyzw;
 // DXBC 161: store_structured u0.xyzw, r1.z, l(0x00000000), r0.xyzw
 uvec4 t161=r0.xyzw;
 waterCells[(uvec4(r1.z)).x]=t161;
 // DXBC 162: ret
 return;
}
