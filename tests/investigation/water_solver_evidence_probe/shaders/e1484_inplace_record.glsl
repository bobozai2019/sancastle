#[compute]
#version 450
// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.
// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
layout(set=0,binding=2,std430) readonly buffer Auxiliary {uvec4 auxiliaryCells[];};
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

 // DXBC 0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t0=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r0.x=t0.x;
 // DXBC 1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot1=(vThreadID.y*512u+vThreadID.x)*2u+0u;
 observedStream[streamSlot1]=uvec4((uvec4(r0.x)).x,0u,15u,1u);
 uvec4 cell1=waterCells[(uvec4(r0.x)).x];
 uvec4 t1=uvec4(0u);
 t1.x=cell1.x;
 t1.y=cell1.y;
 t1.z=cell1.z;
 t1.w=cell1.w;
 r1.xyzw=t1.xyzw;
 uvec4 streamValue1=uvec4(0u);
 streamValue1.xyzw=r1.xyzw;
 observedStream[streamSlot1+1u]=streamValue1;
 // DXBC 2: itof r0.yz, vThreadID.xxyx
 precise vec4 f2=vec4(ivec4(vThreadID.xxyx));
 uvec4 t2=floatBitsToUint(f2);
 r0.yz=t2.yz;
 // DXBC 3: add r0.yz, r0.yyzy, l(0x00000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f3=(uintBitsToFloat(r0.yyzy)+uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t3=floatBitsToUint(f3);
 r0.yz=t3.yz;
 // DXBC 4: itof r2.xy, cb0[155].xyxx
 precise vec4 f4=vec4(ivec4(constants[155].xyxx));
 uvec4 t4=floatBitsToUint(f4);
 r2.xy=t4.xy;
 // DXBC 5: div_sat r0.yz, r0.yyzy, r2.xxyx
 precise vec4 f5=clamp((uintBitsToFloat(r0.yyzy)/uintBitsToFloat(r2.xxyx)),vec4(0),vec4(1));
 uvec4 t5=floatBitsToUint(f5);
 r0.yz=t5.yz;
 // DXBC 6: itof r2.xy, cb0[153].xyxx
 precise vec4 f6=vec4(ivec4(constants[153].xyxx));
 uvec4 t6=floatBitsToUint(f6);
 r2.xy=t6.xy;
 // DXBC 7: mad r0.yz, r0.yyzy, r2.xxyx, l(0x00000000, 0xbf000000, 0xbf000000, 0x00000000)
 precise vec4 f7=fma(uintBitsToFloat(r0.yyzy),uintBitsToFloat(r2.xxyx),uintBitsToFloat(uvec4(0x00000000u,0xbf000000u,0xbf000000u,0x00000000u)));
 uvec4 t7=floatBitsToUint(f7);
 r0.yz=t7.yz;
 // DXBC 8: round_ni r2.xy, r0.yzyy
 precise vec4 f8=floor(uintBitsToFloat(r0.yzyy));
 uvec4 t8=floatBitsToUint(f8);
 r2.xy=t8.xy;
 // DXBC 9: frc r0.yz, r0.yyzy
 precise vec4 f9=fract(uintBitsToFloat(r0.yyzy));
 uvec4 t9=floatBitsToUint(f9);
 r0.yz=t9.yz;
 // DXBC 10: ftoi r2.xy, r2.xyxx
 uvec4 t10=uvec4(ivec4(uintBitsToFloat(r2.xyxx)));
 r2.xy=t10.xy;
 // DXBC 11: iadd r2.zw, r2.xxxy, l(0x00000000, 0x00000000, 0x00000001, 0x00000001)
 uvec4 t11=(r2.xxxy+uvec4(0x00000000u,0x00000000u,0x00000001u,0x00000001u));
 r2.zw=t11.zw;
 // DXBC 12: imax r2.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t12=uvec4(max(ivec4(r2.zzzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r2.zw=t12.zw;
 // DXBC 13: iadd r3.xy, cb0[153].xyxx, l(0xffffffff, 0xffffffff, 0x00000000, 0x00000000)
 uvec4 t13=(constants[153].xyxx+uvec4(0xffffffffu,0xffffffffu,0x00000000u,0x00000000u));
 r3.xy=t13.xy;
 // DXBC 14: imin r2.zw, r2.zzzw, r3.xxxy
 uvec4 t14=uvec4(min(ivec4(r2.zzzw),ivec4(r3.xxxy)));
 r2.zw=t14.zw;
 // DXBC 15: imad r0.w, r2.w, cb0[153].x, r2.z
 uvec4 t15=(uvec4(r2.w)*uvec4(constants[153].x)+uvec4(r2.z));
 r0.w=t15.w;
 // DXBC 16: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r0.w, l(0x00000008), t0.xxxy
 uvec4 cell16=auxiliaryCells[(uvec4(r0.w)).x];
 uvec4 t16=uvec4(0u);
 t16.z=cell16.z;
 t16.w=cell16.w;
 r2.zw=t16.zw;
 // DXBC 17: ushr r0.w, r2.z, l(0x0000000c)
 uvec4 t17=(uvec4(r2.z)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r0.w=t17.w;
 // DXBC 18: bfi r0.w, l(0x0000000c), l(0x00000014), r2.w, r0.w
 uvec4 t18=uvec4(bitfieldInsert((uvec4(r0.w)).x,(uvec4(r2.w)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r0.w)).y,(uvec4(r2.w)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r0.w)).z,(uvec4(r2.w)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r0.w)).w,(uvec4(r2.w)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r0.w=t18.w;
 // DXBC 19: and r2.z, r2.z, l(0x00000fff)
 uvec4 t19=(uvec4(r2.z)&uvec4(0x00000fffu));
 r2.z=t19.z;
 // DXBC 20: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t20=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t20.w;
 // DXBC 21: utof r0.w, r0.w
 precise vec4 f21=vec4(uvec4(r0.w));
 uvec4 t21=floatBitsToUint(f21);
 r0.w=t21.w;
 // DXBC 22: iadd r4.xyzw, r2.xyxy, l(0x00000001, 0x00000000, 0x00000000, 0x00000001)
 uvec4 t22=(r2.xyxy+uvec4(0x00000001u,0x00000000u,0x00000000u,0x00000001u));
 r4.xyzw=t22.xyzw;
 // DXBC 23: imax r2.xy, r2.xyxx, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t23=uvec4(max(ivec4(r2.xyxx),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r2.xy=t23.xy;
 // DXBC 24: imin r2.xy, r3.xyxx, r2.xyxx
 uvec4 t24=uvec4(min(ivec4(r3.xyxx),ivec4(r2.xyxx)));
 r2.xy=t24.xy;
 // DXBC 25: imad r2.x, r2.y, cb0[153].x, r2.x
 uvec4 t25=(uvec4(r2.y)*uvec4(constants[153].x)+uvec4(r2.x));
 r2.x=t25.x;
 // DXBC 26: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r2.x, l(0x00000008), t0.xyxx
 uvec4 cell26=auxiliaryCells[(uvec4(r2.x)).x];
 uvec4 t26=uvec4(0u);
 t26.x=cell26.z;
 t26.y=cell26.w;
 r2.xy=t26.xy;
 // DXBC 27: imax r4.xyzw, r4.xyzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t27=uvec4(max(ivec4(r4.xyzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r4.xyzw=t27.xyzw;
 // DXBC 28: imin r3.xyzw, r3.xyxy, r4.xyzw
 uvec4 t28=uvec4(min(ivec4(r3.xyxy),ivec4(r4.xyzw)));
 r3.xyzw=t28.xyzw;
 // DXBC 29: imad r3.xy, r3.ywyy, cb0[153].xxxx, r3.xzxx
 uvec4 t29=(r3.ywyy*constants[153].xxxx+r3.xzxx);
 r3.xy=t29.xy;
 // DXBC 30: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.yz, r3.y, l(0x00000008), t0.xxyx
 uvec4 cell30=auxiliaryCells[(uvec4(r3.y)).x];
 uvec4 t30=uvec4(0u);
 t30.y=cell30.z;
 t30.z=cell30.w;
 r3.yz=t30.yz;
 // DXBC 31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xw, r3.x, l(0x00000008), t0.xxxy
 uvec4 cell31=auxiliaryCells[(uvec4(r3.x)).x];
 uvec4 t31=uvec4(0u);
 t31.x=cell31.z;
 t31.w=cell31.w;
 r3.xw=t31.xw;
 // DXBC 32: ushr r2.w, r3.y, l(0x0000000c)
 uvec4 t32=(uvec4(r3.y)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.w=t32.w;
 // DXBC 33: bfi r2.w, l(0x0000000c), l(0x00000014), r3.z, r2.w
 uvec4 t33=uvec4(bitfieldInsert((uvec4(r2.w)).x,(uvec4(r3.z)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.w)).y,(uvec4(r3.z)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.w)).z,(uvec4(r3.z)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.w)).w,(uvec4(r3.z)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.w=t33.w;
 // DXBC 34: and r3.y, r3.y, l(0x00000fff)
 uvec4 t34=(uvec4(r3.y)&uvec4(0x00000fffu));
 r3.y=t34.y;
 // DXBC 35: utof r3.y, r3.y
 precise vec4 f35=vec4(uvec4(r3.y));
 uvec4 t35=floatBitsToUint(f35);
 r3.y=t35.y;
 // DXBC 36: mul r3.y, r3.y, l(0x3b21a3b5)
 precise vec4 f36=(uintBitsToFloat(uvec4(r3.y))*uintBitsToFloat(uvec4(0x3b21a3b5u)));
 uvec4 t36=floatBitsToUint(f36);
 r3.y=t36.y;
 // DXBC 37: and r2.w, r2.w, l(0x00ffffff)
 uvec4 t37=(uvec4(r2.w)&uvec4(0x00ffffffu));
 r2.w=t37.w;
 // DXBC 38: utof r2.zw, r2.zzzw
 precise vec4 f38=vec4(r2.zzzw);
 uvec4 t38=floatBitsToUint(f38);
 r2.zw=t38.zw;
 // DXBC 39: mul r2.w, r2.w, l(0x3521999b)
 precise vec4 f39=(uintBitsToFloat(uvec4(r2.w))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t39=floatBitsToUint(f39);
 r2.w=t39.w;
 // DXBC 40: mad r0.w, r0.w, l(0x3521999b), -r2.w
 precise vec4 f40=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.w)))));
 uvec4 t40=floatBitsToUint(f40);
 r0.w=t40.w;
 // DXBC 41: mad r0.w, r0.y, r0.w, r2.w
 precise vec4 f41=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r2.w)));
 uvec4 t41=floatBitsToUint(f41);
 r0.w=t41.w;
 // DXBC 42: ushr r2.w, r3.x, l(0x0000000c)
 uvec4 t42=(uvec4(r3.x)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.w=t42.w;
 // DXBC 43: bfi r2.w, l(0x0000000c), l(0x00000014), r3.w, r2.w
 uvec4 t43=uvec4(bitfieldInsert((uvec4(r2.w)).x,(uvec4(r3.w)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.w)).y,(uvec4(r3.w)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.w)).z,(uvec4(r3.w)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.w)).w,(uvec4(r3.w)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.w=t43.w;
 // DXBC 44: and r3.x, r3.x, l(0x00000fff)
 uvec4 t44=(uvec4(r3.x)&uvec4(0x00000fffu));
 r3.x=t44.x;
 // DXBC 45: utof r3.x, r3.x
 precise vec4 f45=vec4(uvec4(r3.x));
 uvec4 t45=floatBitsToUint(f45);
 r3.x=t45.x;
 // DXBC 46: and r2.w, r2.w, l(0x00ffffff)
 uvec4 t46=(uvec4(r2.w)&uvec4(0x00ffffffu));
 r2.w=t46.w;
 // DXBC 47: ushr r3.z, r2.x, l(0x0000000c)
 uvec4 t47=(uvec4(r2.x)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r3.z=t47.z;
 // DXBC 48: bfi r2.y, l(0x0000000c), l(0x00000014), r2.y, r3.z
 uvec4 t48=uvec4(bitfieldInsert((uvec4(r3.z)).x,(uvec4(r2.y)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r3.z)).y,(uvec4(r2.y)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r3.z)).z,(uvec4(r2.y)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r3.z)).w,(uvec4(r2.y)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.y=t48.y;
 // DXBC 49: and r2.xy, r2.xyxx, l(0x00000fff, 0x00ffffff, 0x00000000, 0x00000000)
 uvec4 t49=(r2.xyxx&uvec4(0x00000fffu,0x00ffffffu,0x00000000u,0x00000000u));
 r2.xy=t49.xy;
 // DXBC 50: utof r2.xyw, r2.xyxw
 precise vec4 f50=vec4(r2.xyxw);
 uvec4 t50=floatBitsToUint(f50);
 r2.xyw=t50.xyw;
 // DXBC 51: mul r2.xy, r2.xyxx, l(0x3b21a3b5, 0x3521999b, 0x00000000, 0x00000000)
 precise vec4 f51=(uintBitsToFloat(r2.xyxx)*uintBitsToFloat(uvec4(0x3b21a3b5u,0x3521999bu,0x00000000u,0x00000000u)));
 uvec4 t51=floatBitsToUint(f51);
 r2.xy=t51.xy;
 // DXBC 52: mad r2.w, r2.w, l(0x3521999b), -r2.y
 precise vec4 f52=fma(uintBitsToFloat(uvec4(r2.w)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.y)))));
 uvec4 t52=floatBitsToUint(f52);
 r2.w=t52.w;
 // DXBC 53: mad r2.y, r0.y, r2.w, r2.y
 precise vec4 f53=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.w)),uintBitsToFloat(uvec4(r2.y)));
 uvec4 t53=floatBitsToUint(f53);
 r2.y=t53.y;
 // DXBC 54: add r0.w, r0.w, -r2.y
 precise vec4 f54=(uintBitsToFloat(uvec4(r0.w))+uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.y)))));
 uvec4 t54=floatBitsToUint(f54);
 r0.w=t54.w;
 // DXBC 55: mad r0.w, r0.z, r0.w, r2.y
 precise vec4 f55=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r2.y)));
 uvec4 t55=floatBitsToUint(f55);
 r0.w=t55.w;
 // DXBC 56: mad r2.y, r2.z, l(0x3b21a3b5), -r3.y
 precise vec4 f56=fma(uintBitsToFloat(uvec4(r2.z)),uintBitsToFloat(uvec4(0x3b21a3b5u)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r3.y)))));
 uvec4 t56=floatBitsToUint(f56);
 r2.y=t56.y;
 // DXBC 57: mad r2.y, r0.y, r2.y, r3.y
 precise vec4 f57=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.y)),uintBitsToFloat(uvec4(r3.y)));
 uvec4 t57=floatBitsToUint(f57);
 r2.y=t57.y;
 // DXBC 58: mad r2.z, r3.x, l(0x3b21a3b5), -r2.x
 precise vec4 f58=fma(uintBitsToFloat(uvec4(r3.x)),uintBitsToFloat(uvec4(0x3b21a3b5u)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.x)))));
 uvec4 t58=floatBitsToUint(f58);
 r2.z=t58.z;
 // DXBC 59: mad r0.y, r0.y, r2.z, r2.x
 precise vec4 f59=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.z)),uintBitsToFloat(uvec4(r2.x)));
 uvec4 t59=floatBitsToUint(f59);
 r0.y=t59.y;
 // DXBC 60: add r2.x, -r0.y, r2.y
 precise vec4 f60=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.y))))+uintBitsToFloat(uvec4(r2.y)));
 uvec4 t60=floatBitsToUint(f60);
 r2.x=t60.x;
 // DXBC 61: mad r0.y, r0.z, r2.x, r0.y
 precise vec4 f61=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t61=floatBitsToUint(f61);
 r0.y=t61.y;
 // DXBC 62: max r0.y, r0.y, r0.w
 precise vec4 f62=max(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r0.w)));
 uvec4 t62=floatBitsToUint(f62);
 r0.y=t62.y;
 // DXBC 63: mul_sat r0.y, r0.y, l(0x3dcac5b3)
 precise vec4 f63=clamp((uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(0x3dcac5b3u))),vec4(0),vec4(1));
 uvec4 t63=floatBitsToUint(f63);
 r0.y=t63.y;
 // DXBC 64: mad r0.y, r0.y, l(0x4b7fffff), l(0x3f000000)
 precise vec4 f64=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x4b7fffffu)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t64=floatBitsToUint(f64);
 r0.y=t64.y;
 // DXBC 65: ftou r0.y, r0.y
 uvec4 t65=uvec4(uintBitsToFloat(uvec4(r0.y)));
 r0.y=t65.y;
 // DXBC 66: ushr r0.z, r0.y, l(0x00000008)
 uvec4 t66=(uvec4(r0.y)>>(uvec4(0x00000008u)&uvec4(31u)));
 r0.z=t66.z;
 // DXBC 67: ubfe r2.xyz, l(0x00000008, 0x00000008, 0x00000004, 0x00000000), l(0x00000008, 0x00000010, 0x00000018, 0x00000000), r1.xwwx
 uvec4 t67=uvec4(bitfieldExtract((r1.xwwx).x,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).x),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).x)),bitfieldExtract((r1.xwwx).y,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).y),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).y)),bitfieldExtract((r1.xwwx).z,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).z),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).z)),bitfieldExtract((r1.xwwx).w,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).w),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).w)));
 r2.xyz=t67.xyz;
 // DXBC 68: utof r2.xyz, r2.xyzx
 precise vec4 f68=vec4(r2.xyzx);
 uvec4 t68=floatBitsToUint(f68);
 r2.xyz=t68.xyz;
 // DXBC 69: mad r2.xyz, r2.xyzx, l(0x3f800000, 0x3f800000, 0x3f800000, 0x00000000), l(0x3f000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f69=fma(uintBitsToFloat(r2.xyzx),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t69=floatBitsToUint(f69);
 r2.xyz=t69.xyz;
 // DXBC 70: ftou r2.xyz, r2.xyzx
 uvec4 t70=uvec4(uintBitsToFloat(r2.xyzx));
 r2.xyz=t70.xyz;
 // DXBC 71: ishl r0.w, r2.y, l(0x00000010)
 uvec4 t71=(uvec4(r2.y)<<(uvec4(0x00000010u)&uvec4(31u)));
 r0.w=t71.w;
 // DXBC 72: or r0.z, r0.w, r0.z
 uvec4 t72=(uvec4(r0.w)|uvec4(r0.z));
 r0.z=t72.z;
 // DXBC 73: imad r3.w, r2.z, l(0x01000000), r0.z
 uvec4 t73=(uvec4(r2.z)*uvec4(0x01000000u)+uvec4(r0.z));
 r3.w=t73.w;
 // DXBC 74: and r0.zw, r1.xxxz, l(0x00000000, 0x00000000, 0x000000ff, 0x00ffffff)
 uvec4 t74=(r1.xxxz&uvec4(0x00000000u,0x00000000u,0x000000ffu,0x00ffffffu));
 r0.zw=t74.zw;
 // DXBC 75: utof r0.zw, r0.zzzw
 precise vec4 f75=vec4(r0.zzzw);
 uvec4 t75=floatBitsToUint(f75);
 r0.zw=t75.zw;
 // DXBC 76: mad r0.zw, r0.zzzw, l(0x00000000, 0x00000000, 0x3f800000, 0x3f800000), l(0x00000000, 0x00000000, 0x3f000000, 0x3f000000)
 precise vec4 f76=fma(uintBitsToFloat(r0.zzzw),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f800000u,0x3f800000u)),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f000000u,0x3f000000u)));
 uvec4 t76=floatBitsToUint(f76);
 r0.zw=t76.zw;
 // DXBC 77: ftou r0.zw, r0.zzzw
 uvec4 t77=uvec4(uintBitsToFloat(r0.zzzw));
 r0.zw=t77.zw;
 // DXBC 78: bfi r3.z, l(0x00000008), l(0x00000018), r0.y, r0.w
 uvec4 t78=uvec4(bitfieldInsert((uvec4(r0.w)).x,(uvec4(r0.y)).x,int((uvec4(0x00000018u)).x),int((uvec4(0x00000008u)).x)),bitfieldInsert((uvec4(r0.w)).y,(uvec4(r0.y)).y,int((uvec4(0x00000018u)).y),int((uvec4(0x00000008u)).y)),bitfieldInsert((uvec4(r0.w)).z,(uvec4(r0.y)).z,int((uvec4(0x00000018u)).z),int((uvec4(0x00000008u)).z)),bitfieldInsert((uvec4(r0.w)).w,(uvec4(r0.y)).w,int((uvec4(0x00000018u)).w),int((uvec4(0x00000008u)).w)));
 r3.z=t78.z;
 // DXBC 79: imad r0.y, r2.x, l(0x00000100), r0.z
 uvec4 t79=(uvec4(r2.x)*uvec4(0x00000100u)+uvec4(r0.z));
 r0.y=t79.y;
 // DXBC 80: ushr r1.xzw, r1.xxyw, l(0x00000010, 0x00000000, 0x00000008, 0x0000001c)
 uvec4 t80=(r1.xxyw>>(uvec4(0x00000010u,0x00000000u,0x00000008u,0x0000001cu)&uvec4(31u)));
 r1.xzw=t80.xzw;
 // DXBC 81: bfi r0.z, l(0x00000010), l(0x00000010), r1.y, r1.x
 uvec4 t81=uvec4(bitfieldInsert((uvec4(r1.x)).x,(uvec4(r1.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r1.x)).y,(uvec4(r1.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r1.x)).z,(uvec4(r1.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r1.x)).w,(uvec4(r1.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.z=t81.z;
 // DXBC 82: utof r1.xy, r1.zwzz
 precise vec4 f82=vec4(r1.zwzz);
 uvec4 t82=floatBitsToUint(f82);
 r1.xy=t82.xy;
 // DXBC 83: mad r1.xy, r1.xyxx, l(0x3f800000, 0x3f800000, 0x00000000, 0x00000000), l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f83=fma(uintBitsToFloat(r1.xyxx),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t83=floatBitsToUint(f83);
 r1.xy=t83.xy;
 // DXBC 84: ftou r1.xy, r1.xyxx
 uvec4 t84=uvec4(uintBitsToFloat(r1.xyxx));
 r1.xy=t84.xy;
 // DXBC 85: ishl r1.xy, r1.xyxx, l(0x00000008, 0x0000001c, 0x00000000, 0x00000000)
 uvec4 t85=(r1.xyxx<<(uvec4(0x00000008u,0x0000001cu,0x00000000u,0x00000000u)&uvec4(31u)));
 r1.xy=t85.xy;
 // DXBC 86: and r0.z, r0.z, l(0x00ffffff)
 uvec4 t86=(uvec4(r0.z)&uvec4(0x00ffffffu));
 r0.z=t86.z;
 // DXBC 87: utof r0.z, r0.z
 precise vec4 f87=vec4(uvec4(r0.z));
 uvec4 t87=floatBitsToUint(f87);
 r0.z=t87.z;
 // DXBC 88: mad r0.z, r0.z, l(0x3f800000), l(0x3f000000)
 precise vec4 f88=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x3f800000u)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t88=floatBitsToUint(f88);
 r0.z=t88.z;
 // DXBC 89: ftou r0.z, r0.z
 uvec4 t89=uvec4(uintBitsToFloat(uvec4(r0.z)));
 r0.z=t89.z;
 // DXBC 90: bfi r3.x, l(0x00000010), l(0x00000010), r0.z, r0.y
 uvec4 t90=uvec4(bitfieldInsert((uvec4(r0.y)).x,(uvec4(r0.z)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.y)).y,(uvec4(r0.z)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.y)).z,(uvec4(r0.z)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.y)).w,(uvec4(r0.z)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r3.x=t90.x;
 // DXBC 91: ushr r0.y, r0.z, l(0x00000010)
 uvec4 t91=(uvec4(r0.z)>>(uvec4(0x00000010u)&uvec4(31u)));
 r0.y=t91.y;
 // DXBC 92: or r3.y, r1.x, r0.y
 uvec4 t92=(uvec4(r1.x)|uvec4(r0.y));
 r3.y=t92.y;
 // DXBC 93: mov r1.z, l(0x00000000)
 uvec4 t93=uvec4(0x00000000u);
 r1.z=t93.z;
 // DXBC 94: iadd r1.xyzw, r1.zzzy, r3.xyzw
 uvec4 t94=(r1.zzzy+r3.xyzw);
 r1.xyzw=t94.xyzw;
 // DXBC 95: store_structured u0.xyzw, r0.x, l(0x00000000), r1.xyzw
 uvec4 t95=r1.xyzw;
 waterCells[(uvec4(r0.x)).x]=t95;
 // DXBC 96: ret
 return;
}
