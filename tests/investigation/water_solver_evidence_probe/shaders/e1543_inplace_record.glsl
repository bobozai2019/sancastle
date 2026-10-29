#[compute]
#version 450
// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.
// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
float dx_dp2(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float sum=m0+m1;return sum;}
float dx_dp3(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float m2=a.z*b.z;precise float sum=m0+m1;precise float total=sum+m2;return total;}
layout(set=0,binding=5,std430) buffer StreamOutput {uvec4 observedStream[];};
void main(){
 uvec4 vThreadID=uvec4(gl_GlobalInvocationID,0u);
 uvec4 r0=uvec4(0u);
 uvec4 r1=uvec4(0u);
 uvec4 r2=uvec4(0u);
 uvec4 r3=uvec4(0u);
 uvec4 r4=uvec4(0u);
 uvec4 r5=uvec4(0u);

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
 // DXBC 5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xy, r0.x, l(0x00000008), u0.xyxx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot5=(vThreadID.y*512u+vThreadID.x)*10u+0u;
 observedStream[streamSlot5]=uvec4((uvec4(r0.x)).x,8u,3u,5u);
 uvec4 cell5=waterCells[(uvec4(r0.x)).x];
 uvec4 t5=uvec4(0u);
 t5.x=cell5.z;
 t5.y=cell5.w;
 r0.xy=t5.xy;
 uvec4 streamValue5=uvec4(0u);
 streamValue5.xy=r0.xy;
 observedStream[streamSlot5+1u]=streamValue5;
 // DXBC 6: imad r0.z, r0.w, cb0[155].x, r0.z
 uvec4 t6=(uvec4(r0.w)*uvec4(constants[155].x)+uvec4(r0.z));
 r0.z=t6.z;
 // DXBC 7: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(0x00000008), u0.xxxy
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot7=(vThreadID.y*512u+vThreadID.x)*10u+2u;
 observedStream[streamSlot7]=uvec4((uvec4(r0.z)).x,8u,12u,7u);
 uvec4 cell7=waterCells[(uvec4(r0.z)).x];
 uvec4 t7=uvec4(0u);
 t7.z=cell7.z;
 t7.w=cell7.w;
 r0.zw=t7.zw;
 uvec4 streamValue7=uvec4(0u);
 streamValue7.zw=r0.zw;
 observedStream[streamSlot7+1u]=streamValue7;
 // DXBC 8: iadd r2.xyzw, vThreadID.xyxy, l(0x00000000, 0xffffffff, 0x00000000, 0x00000001)
 uvec4 t8=(vThreadID.xyxy+uvec4(0x00000000u,0xffffffffu,0x00000000u,0x00000001u));
 r2.xyzw=t8.xyzw;
 // DXBC 9: imax r2.y, r2.y, l(0x00000000)
 uvec4 t9=uvec4(max(ivec4(uvec4(r2.y)),ivec4(uvec4(0x00000000u))));
 r2.y=t9.y;
 // DXBC 10: imin r1.zw, r1.xxxy, r2.zzzw
 uvec4 t10=uvec4(min(ivec4(r1.xxxy),ivec4(r2.zzzw)));
 r1.zw=t10.zw;
 // DXBC 11: imin r1.xy, r1.xyxx, r2.xyxx
 uvec4 t11=uvec4(min(ivec4(r1.xyxx),ivec4(r2.xyxx)));
 r1.xy=t11.xy;
 // DXBC 12: imad r1.x, r1.y, cb0[155].x, r1.x
 uvec4 t12=(uvec4(r1.y)*uvec4(constants[155].x)+uvec4(r1.x));
 r1.x=t12.x;
 // DXBC 13: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(0x00000008), u0.xyxx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot13=(vThreadID.y*512u+vThreadID.x)*10u+4u;
 observedStream[streamSlot13]=uvec4((uvec4(r1.x)).x,8u,3u,13u);
 uvec4 cell13=waterCells[(uvec4(r1.x)).x];
 uvec4 t13=uvec4(0u);
 t13.x=cell13.z;
 t13.y=cell13.w;
 r1.xy=t13.xy;
 uvec4 streamValue13=uvec4(0u);
 streamValue13.xy=r1.xy;
 observedStream[streamSlot13+1u]=streamValue13;
 // DXBC 14: imad r1.z, r1.w, cb0[155].x, r1.z
 uvec4 t14=(uvec4(r1.w)*uvec4(constants[155].x)+uvec4(r1.z));
 r1.z=t14.z;
 // DXBC 15: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(0x00000008), u0.xxxy
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot15=(vThreadID.y*512u+vThreadID.x)*10u+6u;
 observedStream[streamSlot15]=uvec4((uvec4(r1.z)).x,8u,12u,15u);
 uvec4 cell15=waterCells[(uvec4(r1.z)).x];
 uvec4 t15=uvec4(0u);
 t15.z=cell15.z;
 t15.w=cell15.w;
 r1.zw=t15.zw;
 uvec4 streamValue15=uvec4(0u);
 streamValue15.zw=r1.zw;
 observedStream[streamSlot15+1u]=streamValue15;
 // DXBC 16: imad r2.x, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t16=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r2.x=t16.x;
 // DXBC 17: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r2.x, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot17=(vThreadID.y*512u+vThreadID.x)*10u+8u;
 observedStream[streamSlot17]=uvec4((uvec4(r2.x)).x,0u,15u,17u);
 uvec4 cell17=waterCells[(uvec4(r2.x)).x];
 uvec4 t17=uvec4(0u);
 t17.x=cell17.x;
 t17.y=cell17.y;
 t17.z=cell17.z;
 t17.w=cell17.w;
 r3.xyzw=t17.xyzw;
 uvec4 streamValue17=uvec4(0u);
 streamValue17.xyzw=r3.xyzw;
 observedStream[streamSlot17+1u]=streamValue17;
 // DXBC 18: ushr r2.y, r0.z, l(0x00000018)
 uvec4 t18=(uvec4(r0.z)>>(uvec4(0x00000018u)&uvec4(31u)));
 r2.y=t18.y;
 // DXBC 19: bfi r0.w, l(0x00000018), l(0x00000008), r0.w, r2.y
 uvec4 t19=uvec4(bitfieldInsert((uvec4(r2.y)).x,(uvec4(r0.w)).x,int((uvec4(0x00000008u)).x),int((uvec4(0x00000018u)).x)),bitfieldInsert((uvec4(r2.y)).y,(uvec4(r0.w)).y,int((uvec4(0x00000008u)).y),int((uvec4(0x00000018u)).y)),bitfieldInsert((uvec4(r2.y)).z,(uvec4(r0.w)).z,int((uvec4(0x00000008u)).z),int((uvec4(0x00000018u)).z)),bitfieldInsert((uvec4(r2.y)).w,(uvec4(r0.w)).w,int((uvec4(0x00000008u)).w),int((uvec4(0x00000018u)).w)));
 r0.w=t19.w;
 // DXBC 20: and r0.zw, r0.zzzw, l(0x00000000, 0x00000000, 0x00ffffff, 0x00ffffff)
 uvec4 t20=(r0.zzzw&uvec4(0x00000000u,0x00000000u,0x00ffffffu,0x00ffffffu));
 r0.zw=t20.zw;
 // DXBC 21: utof r0.zw, r0.zzzw
 precise vec4 f21=vec4(r0.zzzw);
 uvec4 t21=floatBitsToUint(f21);
 r0.zw=t21.zw;
 // DXBC 22: mad r0.z, r0.z, l(0x3521999b), l(0xbd4ccccd)
 precise vec4 f22=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t22=floatBitsToUint(f22);
 r0.z=t22.z;
 // DXBC 23: max r0.z, r0.z, l(0x00000000)
 precise vec4 f23=max(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t23=floatBitsToUint(f23);
 r0.z=t23.z;
 // DXBC 24: mad r0.z, r0.w, l(0x3521999b), r0.z
 precise vec4 f24=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.z)));
 uvec4 t24=floatBitsToUint(f24);
 r0.z=t24.z;
 // DXBC 25: ushr r0.w, r0.x, l(0x00000018)
 uvec4 t25=(uvec4(r0.x)>>(uvec4(0x00000018u)&uvec4(31u)));
 r0.w=t25.w;
 // DXBC 26: bfi r0.y, l(0x00000018), l(0x00000008), r0.y, r0.w
 uvec4 t26=uvec4(bitfieldInsert((uvec4(r0.w)).x,(uvec4(r0.y)).x,int((uvec4(0x00000008u)).x),int((uvec4(0x00000018u)).x)),bitfieldInsert((uvec4(r0.w)).y,(uvec4(r0.y)).y,int((uvec4(0x00000008u)).y),int((uvec4(0x00000018u)).y)),bitfieldInsert((uvec4(r0.w)).z,(uvec4(r0.y)).z,int((uvec4(0x00000008u)).z),int((uvec4(0x00000018u)).z)),bitfieldInsert((uvec4(r0.w)).w,(uvec4(r0.y)).w,int((uvec4(0x00000008u)).w),int((uvec4(0x00000018u)).w)));
 r0.y=t26.y;
 // DXBC 27: and r0.xy, r0.xyxx, l(0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000)
 uvec4 t27=(r0.xyxx&uvec4(0x00ffffffu,0x00ffffffu,0x00000000u,0x00000000u));
 r0.xy=t27.xy;
 // DXBC 28: utof r0.xy, r0.xyxx
 precise vec4 f28=vec4(r0.xyxx);
 uvec4 t28=floatBitsToUint(f28);
 r0.xy=t28.xy;
 // DXBC 29: mad r0.x, r0.x, l(0x3521999b), l(0xbd4ccccd)
 precise vec4 f29=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t29=floatBitsToUint(f29);
 r0.x=t29.x;
 // DXBC 30: max r0.x, r0.x, l(0x00000000)
 precise vec4 f30=max(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t30=floatBitsToUint(f30);
 r0.x=t30.x;
 // DXBC 31: mad r0.x, r0.y, l(0x3521999b), r0.x
 precise vec4 f31=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.x)));
 uvec4 t31=floatBitsToUint(f31);
 r0.x=t31.x;
 // DXBC 32: add r0.x, -r0.z, r0.x
 precise vec4 f32=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.z))))+uintBitsToFloat(uvec4(r0.x)));
 uvec4 t32=floatBitsToUint(f32);
 r0.x=t32.x;
 // DXBC 33: ushr r0.z, r1.z, l(0x00000018)
 uvec4 t33=(uvec4(r1.z)>>(uvec4(0x00000018u)&uvec4(31u)));
 r0.z=t33.z;
 // DXBC 34: bfi r0.z, l(0x00000018), l(0x00000008), r1.w, r0.z
 uvec4 t34=uvec4(bitfieldInsert((uvec4(r0.z)).x,(uvec4(r1.w)).x,int((uvec4(0x00000008u)).x),int((uvec4(0x00000018u)).x)),bitfieldInsert((uvec4(r0.z)).y,(uvec4(r1.w)).y,int((uvec4(0x00000008u)).y),int((uvec4(0x00000018u)).y)),bitfieldInsert((uvec4(r0.z)).z,(uvec4(r1.w)).z,int((uvec4(0x00000008u)).z),int((uvec4(0x00000018u)).z)),bitfieldInsert((uvec4(r0.z)).w,(uvec4(r1.w)).w,int((uvec4(0x00000008u)).w),int((uvec4(0x00000018u)).w)));
 r0.z=t34.z;
 // DXBC 35: and r0.w, r1.z, l(0x00ffffff)
 uvec4 t35=(uvec4(r1.z)&uvec4(0x00ffffffu));
 r0.w=t35.w;
 // DXBC 36: utof r0.w, r0.w
 precise vec4 f36=vec4(uvec4(r0.w));
 uvec4 t36=floatBitsToUint(f36);
 r0.w=t36.w;
 // DXBC 37: mad r0.w, r0.w, l(0x3521999b), l(0xbd4ccccd)
 precise vec4 f37=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t37=floatBitsToUint(f37);
 r0.w=t37.w;
 // DXBC 38: max r0.w, r0.w, l(0x00000000)
 precise vec4 f38=max(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t38=floatBitsToUint(f38);
 r0.w=t38.w;
 // DXBC 39: and r0.z, r0.z, l(0x00ffffff)
 uvec4 t39=(uvec4(r0.z)&uvec4(0x00ffffffu));
 r0.z=t39.z;
 // DXBC 40: utof r0.z, r0.z
 precise vec4 f40=vec4(uvec4(r0.z));
 uvec4 t40=floatBitsToUint(f40);
 r0.z=t40.z;
 // DXBC 41: mad r0.z, r0.z, l(0x3521999b), r0.w
 precise vec4 f41=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.w)));
 uvec4 t41=floatBitsToUint(f41);
 r0.z=t41.z;
 // DXBC 42: ushr r0.w, r1.x, l(0x00000018)
 uvec4 t42=(uvec4(r1.x)>>(uvec4(0x00000018u)&uvec4(31u)));
 r0.w=t42.w;
 // DXBC 43: bfi r0.w, l(0x00000018), l(0x00000008), r1.y, r0.w
 uvec4 t43=uvec4(bitfieldInsert((uvec4(r0.w)).x,(uvec4(r1.y)).x,int((uvec4(0x00000008u)).x),int((uvec4(0x00000018u)).x)),bitfieldInsert((uvec4(r0.w)).y,(uvec4(r1.y)).y,int((uvec4(0x00000008u)).y),int((uvec4(0x00000018u)).y)),bitfieldInsert((uvec4(r0.w)).z,(uvec4(r1.y)).z,int((uvec4(0x00000008u)).z),int((uvec4(0x00000018u)).z)),bitfieldInsert((uvec4(r0.w)).w,(uvec4(r1.y)).w,int((uvec4(0x00000008u)).w),int((uvec4(0x00000018u)).w)));
 r0.w=t43.w;
 // DXBC 44: and r1.x, r1.x, l(0x00ffffff)
 uvec4 t44=(uvec4(r1.x)&uvec4(0x00ffffffu));
 r1.x=t44.x;
 // DXBC 45: utof r1.x, r1.x
 precise vec4 f45=vec4(uvec4(r1.x));
 uvec4 t45=floatBitsToUint(f45);
 r1.x=t45.x;
 // DXBC 46: mad r1.x, r1.x, l(0x3521999b), l(0xbd4ccccd)
 precise vec4 f46=fma(uintBitsToFloat(uvec4(r1.x)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t46=floatBitsToUint(f46);
 r1.x=t46.x;
 // DXBC 47: max r1.x, r1.x, l(0x00000000)
 precise vec4 f47=max(uintBitsToFloat(uvec4(r1.x)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t47=floatBitsToUint(f47);
 r1.x=t47.x;
 // DXBC 48: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t48=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t48.w;
 // DXBC 49: utof r0.w, r0.w
 precise vec4 f49=vec4(uvec4(r0.w));
 uvec4 t49=floatBitsToUint(f49);
 r0.w=t49.w;
 // DXBC 50: mad r0.w, r0.w, l(0x3521999b), r1.x
 precise vec4 f50=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r1.x)));
 uvec4 t50=floatBitsToUint(f50);
 r0.w=t50.w;
 // DXBC 51: add r0.y, -r0.z, r0.w
 precise vec4 f51=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.z))))+uintBitsToFloat(uvec4(r0.w)));
 uvec4 t51=floatBitsToUint(f51);
 r0.y=t51.y;
 // DXBC 52: mul r0.xy, r0.xyxx, cb0[154].zwzz
 precise vec4 f52=(uintBitsToFloat(r0.xyxx)*uintBitsToFloat(constants[154].zwzz));
 uvec4 t52=floatBitsToUint(f52);
 r0.xy=t52.xy;
 // DXBC 53: mul r0.xy, r0.xyxx, l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f53=(uintBitsToFloat(r0.xyxx)*uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t53=floatBitsToUint(f53);
 r0.xy=t53.xy;
 // DXBC 54: mov r0.z, l(0x3f800000)
 uvec4 t54=uvec4(0x3f800000u);
 r0.z=t54.z;
 // DXBC 55: dp3 r0.z, r0.xyzx, r0.xyzx
 precise vec4 f55=vec4(dx_dp3(uintBitsToFloat(r0.xyzx),uintBitsToFloat(r0.xyzx)));
 uvec4 t55=floatBitsToUint(f55);
 r0.z=t55.z;
 // DXBC 56: rsq r0.z, r0.z
 precise vec4 f56=inversesqrt(uintBitsToFloat(uvec4(r0.z)));
 uvec4 t56=floatBitsToUint(f56);
 r0.z=t56.z;
 // DXBC 57: mad r0.xy, r0.xyxx, r0.zzzz, l(0x3f800000, 0x3f800000, 0x00000000, 0x00000000)
 precise vec4 f57=fma(uintBitsToFloat(r0.xyxx),uintBitsToFloat(r0.zzzz),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x00000000u,0x00000000u)));
 uvec4 t57=floatBitsToUint(f57);
 r0.xy=t57.xy;
 // DXBC 58: mul_sat r0.xy, r0.xyxx, l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f58=clamp((uintBitsToFloat(r0.xyxx)*uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u))),vec4(0),vec4(1));
 uvec4 t58=floatBitsToUint(f58);
 r0.xy=t58.xy;
 // DXBC 59: mad r0.xy, r0.xyxx, l(0x437f0000, 0x437f0000, 0x00000000, 0x00000000), l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f59=fma(uintBitsToFloat(r0.xyxx),uintBitsToFloat(uvec4(0x437f0000u,0x437f0000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t59=floatBitsToUint(f59);
 r0.xy=t59.xy;
 // DXBC 60: ftou r0.xy, r0.xyxx
 uvec4 t60=uvec4(uintBitsToFloat(r0.xyxx));
 r0.xy=t60.xy;
 // DXBC 61: imad r0.x, r0.y, l(0x00000100), r0.x
 uvec4 t61=(uvec4(r0.y)*uvec4(0x00000100u)+uvec4(r0.x));
 r0.x=t61.x;
 // DXBC 62: ushr r1.xyzw, r3.xyzw, l(0x00000010, 0x00000008, 0x00000018, 0x0000001c)
 uvec4 t62=(r3.xyzw>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x0000001cu)&uvec4(31u)));
 r1.xyzw=t62.xyzw;
 // DXBC 63: bfi r0.yz, l(0x00000000, 0x00000010, 0x00000018, 0x00000000), l(0x00000000, 0x00000010, 0x00000008, 0x00000000), r3.yywy, r1.xxzx
 uvec4 t63=uvec4(bitfieldInsert((r1.xxzx).x,(r3.yywy).x,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r1.xxzx).y,(r3.yywy).y,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r1.xxzx).z,(r3.yywy).z,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r1.xxzx).w,(r3.yywy).w,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).w)));
 r0.yz=t63.yz;
 // DXBC 64: utof r1.xy, r1.ywyy
 precise vec4 f64=vec4(r1.ywyy);
 uvec4 t64=floatBitsToUint(f64);
 r1.xy=t64.xy;
 // DXBC 65: mad r1.xy, r1.xyxx, l(0x3f800000, 0x3f800000, 0x00000000, 0x00000000), l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f65=fma(uintBitsToFloat(r1.xyxx),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t65=floatBitsToUint(f65);
 r1.xy=t65.xy;
 // DXBC 66: ftou r1.xy, r1.xyxx
 uvec4 t66=uvec4(uintBitsToFloat(r1.xyxx));
 r1.xy=t66.xy;
 // DXBC 67: ishl r1.xy, r1.xyxx, l(0x00000008, 0x0000001c, 0x00000000, 0x00000000)
 uvec4 t67=(r1.xyxx<<(uvec4(0x00000008u,0x0000001cu,0x00000000u,0x00000000u)&uvec4(31u)));
 r1.xy=t67.xy;
 // DXBC 68: and r0.yz, r0.yyzy, l(0x00000000, 0x00ffffff, 0x00ffffff, 0x00000000)
 uvec4 t68=(r0.yyzy&uvec4(0x00000000u,0x00ffffffu,0x00ffffffu,0x00000000u));
 r0.yz=t68.yz;
 // DXBC 69: utof r0.yz, r0.yyzy
 precise vec4 f69=vec4(r0.yyzy);
 uvec4 t69=floatBitsToUint(f69);
 r0.yz=t69.yz;
 // DXBC 70: mad r0.yz, r0.yyzy, l(0x00000000, 0x3f800000, 0x3f800000, 0x00000000), l(0x00000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f70=fma(uintBitsToFloat(r0.yyzy),uintBitsToFloat(uvec4(0x00000000u,0x3f800000u,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t70=floatBitsToUint(f70);
 r0.yz=t70.yz;
 // DXBC 71: ftou r0.yz, r0.yyzy
 uvec4 t71=uvec4(uintBitsToFloat(r0.yyzy));
 r0.yz=t71.yz;
 // DXBC 72: bfi r4.x, l(0x00000010), l(0x00000010), r0.y, r0.x
 uvec4 t72=uvec4(bitfieldInsert((uvec4(r0.x)).x,(uvec4(r0.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.x)).y,(uvec4(r0.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.x)).z,(uvec4(r0.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.x)).w,(uvec4(r0.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r4.x=t72.x;
 // DXBC 73: and r0.x, r3.z, l(0x00ffffff)
 uvec4 t73=(uvec4(r3.z)&uvec4(0x00ffffffu));
 r0.x=t73.x;
 // DXBC 74: ubfe r2.yz, l(0x00000000, 0x00000008, 0x00000004, 0x00000000), l(0x00000000, 0x00000010, 0x00000018, 0x00000000), r3.wwww
 uvec4 t74=uvec4(bitfieldExtract((r3.wwww).x,int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).x),int((uvec4(0x00000000u,0x00000008u,0x00000004u,0x00000000u)).x)),bitfieldExtract((r3.wwww).y,int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).y),int((uvec4(0x00000000u,0x00000008u,0x00000004u,0x00000000u)).y)),bitfieldExtract((r3.wwww).z,int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).z),int((uvec4(0x00000000u,0x00000008u,0x00000004u,0x00000000u)).z)),bitfieldExtract((r3.wwww).w,int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).w),int((uvec4(0x00000000u,0x00000008u,0x00000004u,0x00000000u)).w)));
 r2.yz=t74.yz;
 // DXBC 75: utof r2.yz, r2.yyzy
 precise vec4 f75=vec4(r2.yyzy);
 uvec4 t75=floatBitsToUint(f75);
 r2.yz=t75.yz;
 // DXBC 76: mad r2.yz, r2.yyzy, l(0x00000000, 0x3f800000, 0x3f800000, 0x00000000), l(0x00000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f76=fma(uintBitsToFloat(r2.yyzy),uintBitsToFloat(uvec4(0x00000000u,0x3f800000u,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t76=floatBitsToUint(f76);
 r2.yz=t76.yz;
 // DXBC 77: ftou r2.yz, r2.yyzy
 uvec4 t77=uvec4(uintBitsToFloat(r2.yyzy));
 r2.yz=t77.yz;
 // DXBC 78: utof r0.x, r0.x
 precise vec4 f78=vec4(uvec4(r0.x));
 uvec4 t78=floatBitsToUint(f78);
 r0.x=t78.x;
 // DXBC 79: mad r0.x, r0.x, l(0x3f800000), l(0x3f000000)
 precise vec4 f79=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(0x3f800000u)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t79=floatBitsToUint(f79);
 r0.x=t79.x;
 // DXBC 80: ftou r3.x, r0.x
 uvec4 t80=uvec4(uintBitsToFloat(uvec4(r0.x)));
 r3.x=t80.x;
 // DXBC 81: ishl r5.x, r0.z, l(0x00000018)
 uvec4 t81=(uvec4(r0.z)<<(uvec4(0x00000018u)&uvec4(31u)));
 r5.x=t81.x;
 // DXBC 82: ushr r5.yz, r0.yyzy, l(0x00000000, 0x00000010, 0x00000008, 0x00000000)
 uvec4 t82=(r0.yyzy>>(uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)&uvec4(31u)));
 r5.yz=t82.yz;
 // DXBC 83: mov r3.y, l(0x00000000)
 uvec4 t83=uvec4(0x00000000u);
 r3.y=t83.y;
 // DXBC 84: iadd r0.xy, r3.xyxx, r5.xzxx
 uvec4 t84=(r3.xyxx+r5.xzxx);
 r0.xy=t84.xy;
 // DXBC 85: or r4.y, r1.x, r5.y
 uvec4 t85=(uvec4(r1.x)|uvec4(r5.y));
 r4.y=t85.y;
 // DXBC 86: imad r0.y, r2.y, l(0x00010000), r0.y
 uvec4 t86=(uvec4(r2.y)*uvec4(0x00010000u)+uvec4(r0.y));
 r0.y=t86.y;
 // DXBC 87: mov r4.z, r0.x
 uvec4 t87=uvec4(r0.x);
 r4.z=t87.z;
 // DXBC 88: imad r4.w, r2.z, l(0x01000000), r0.y
 uvec4 t88=(uvec4(r2.z)*uvec4(0x01000000u)+uvec4(r0.y));
 r4.w=t88.w;
 // DXBC 89: mov r1.z, l(0x00000000)
 uvec4 t89=uvec4(0x00000000u);
 r1.z=t89.z;
 // DXBC 90: iadd r0.xyzw, r1.zzzy, r4.xyzw
 uvec4 t90=(r1.zzzy+r4.xyzw);
 r0.xyzw=t90.xyzw;
 // DXBC 91: store_structured u0.xyzw, r2.x, l(0x00000000), r0.xyzw
 uvec4 t91=r0.xyzw;
 waterCells[(uvec4(r2.x)).x]=t91;
 // DXBC 92: ret
 return;
}
