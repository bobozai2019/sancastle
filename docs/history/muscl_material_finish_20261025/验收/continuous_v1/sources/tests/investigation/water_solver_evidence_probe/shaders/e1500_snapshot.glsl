#[compute]
#version 450
// Packed-uint DXBC lowering with explicit recorded arithmetic expression models, not original HLSL.
// Explicit readonly snapshot adaptation with separate output, 32x32 threads; not original in-place.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
layout(set=0,binding=4,std430) readonly buffer Snapshot {uvec4 readCells[];};
float dx_dp2(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float sum=m0+m1;return sum;}
float dx_dp3(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float m2=a.z*b.z;precise float sum=m0+m1;precise float total=sum+m2;return total;}
void main(){
 uvec4 vThreadID=uvec4(gl_GlobalInvocationID,0u);
 uvec4 r0=uvec4(0u);
 uvec4 r1=uvec4(0u);
 uvec4 r2=uvec4(0u);
 uvec4 r3=uvec4(0u);
 uvec4 r4=uvec4(0u);
 uvec4 r5=uvec4(0u);
 uvec4 r6=uvec4(0u);

 // DXBC 0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t0=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r0.x=t0.x;
 // DXBC 1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0x00000000), u0.xyzw
 uvec4 cell1=readCells[(uvec4(r0.x)).x];
 uvec4 t1=uvec4(0u);
 t1.x=cell1.x;
 t1.y=cell1.y;
 t1.z=cell1.z;
 t1.w=cell1.w;
 r1.xyzw=t1.xyzw;
 // DXBC 2: ushr r2.xyzw, r1.xyzw, l(0x00000010, 0x00000008, 0x00000018, 0x0000001c)
 uvec4 t2=(r1.xyzw>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x0000001cu)&uvec4(31u)));
 r2.xyzw=t2.xyzw;
 // DXBC 3: bfi r0.yz, l(0x00000000, 0x00000010, 0x00000018, 0x00000000), l(0x00000000, 0x00000010, 0x00000008, 0x00000000), r1.yywy, r2.xxzx
 uvec4 t3=uvec4(bitfieldInsert((r2.xxzx).x,(r1.yywy).x,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r2.xxzx).y,(r1.yywy).y,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r2.xxzx).z,(r1.yywy).z,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r2.xxzx).w,(r1.yywy).w,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).w)));
 r0.yz=t3.yz;
 // DXBC 4: utof r2.xy, r2.ywyy
 precise vec4 f4=vec4(r2.ywyy);
 uvec4 t4=floatBitsToUint(f4);
 r2.xy=t4.xy;
 // DXBC 5: mad r2.zw, r2.xxxy, l(0x00000000, 0x00000000, 0x35000001, 0x3f800000), l(0x00000000, 0x00000000, 0xc0800000, 0x3f000000)
 precise vec4 f5=fma(uintBitsToFloat(r2.xxxy),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x35000001u,0x3f800000u)),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0xc0800000u,0x3f000000u)));
 uvec4 t5=floatBitsToUint(f5);
 r2.zw=t5.zw;
 // DXBC 6: and r0.yz, r0.yyzy, l(0x00000000, 0x00ffffff, 0x00ffffff, 0x00000000)
 uvec4 t6=(r0.yyzy&uvec4(0x00000000u,0x00ffffffu,0x00ffffffu,0x00000000u));
 r0.yz=t6.yz;
 // DXBC 7: utof r0.yz, r0.yyzy
 precise vec4 f7=vec4(r0.yyzy);
 uvec4 t7=floatBitsToUint(f7);
 r0.yz=t7.yz;
 // DXBC 8: mad r2.xy, r0.yzyy, l(0x35000001, 0x3f800000, 0x00000000, 0x00000000), l(0xc0800000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f8=fma(uintBitsToFloat(r0.yzyy),uintBitsToFloat(uvec4(0x35000001u,0x3f800000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0xc0800000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t8=floatBitsToUint(f8);
 r2.xy=t8.xy;
 // DXBC 9: div r0.yz, r2.xxzx, cb0[116].xxzx
 precise vec4 f9=(uintBitsToFloat(r2.xxzx)/uintBitsToFloat(constants[116].xxzx));
 uvec4 t9=floatBitsToUint(f9);
 r0.yz=t9.yz;
 // DXBC 10: ftou r2.xy, r2.ywyy
 uvec4 t10=uvec4(uintBitsToFloat(r2.ywyy));
 r2.xy=t10.xy;
 // DXBC 11: mul r0.yz, r0.yyzy, cb0[158].zzzz
 precise vec4 f11=(uintBitsToFloat(r0.yyzy)*uintBitsToFloat(constants[158].zzzz));
 uvec4 t11=floatBitsToUint(f11);
 r0.yz=t11.yz;
 // DXBC 12: itof r2.zw, vThreadID.xxxy
 precise vec4 f12=vec4(ivec4(vThreadID.xxxy));
 uvec4 t12=floatBitsToUint(f12);
 r2.zw=t12.zw;
 // DXBC 13: add r2.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x3f000000, 0x3f000000)
 precise vec4 f13=(uintBitsToFloat(r2.zzzw)+uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f000000u,0x3f000000u)));
 uvec4 t13=floatBitsToUint(f13);
 r2.zw=t13.zw;
 // DXBC 14: itof r3.xy, cb0[155].xyxx
 precise vec4 f14=vec4(ivec4(constants[155].xyxx));
 uvec4 t14=floatBitsToUint(f14);
 r3.xy=t14.xy;
 // DXBC 15: div_sat r2.zw, r2.zzzw, r3.xxxy
 precise vec4 f15=clamp((uintBitsToFloat(r2.zzzw)/uintBitsToFloat(r3.xxxy)),vec4(0),vec4(1));
 uvec4 t15=floatBitsToUint(f15);
 r2.zw=t15.zw;
 // DXBC 16: mad r0.yz, -r0.yyzy, cb0[157].zzzz, r2.zzwz
 precise vec4 foldedAdvectionDt=uintBitsToFloat(constants[158]).zzzz*uintBitsToFloat(constants[157]).zzzz;
 precise vec4 f16=fma(-uintBitsToFloat(t9),foldedAdvectionDt,uintBitsToFloat(r2.zzwz));
 uvec4 t16=floatBitsToUint(f16);
 r0.yz=t16.yz;
 // DXBC 17: mad r0.yz, r0.yyzy, r3.xxyx, l(0x00000000, 0xbf000000, 0xbf000000, 0x00000000)
 precise vec4 f17=fma(uintBitsToFloat(r0.yyzy),uintBitsToFloat(r3.xxyx),uintBitsToFloat(uvec4(0x00000000u,0xbf000000u,0xbf000000u,0x00000000u)));
 uvec4 t17=floatBitsToUint(f17);
 r0.yz=t17.yz;
 // DXBC 18: round_ni r2.zw, r0.yyyz
 precise vec4 f18=floor(uintBitsToFloat(r0.yyyz));
 uvec4 t18=floatBitsToUint(f18);
 r2.zw=t18.zw;
 // DXBC 19: frc r0.yz, r0.yyzy
 precise vec4 f19=fract(uintBitsToFloat(r0.yyzy));
 uvec4 t19=floatBitsToUint(f19);
 r0.yz=t19.yz;
 // DXBC 20: ftoi r2.zw, r2.zzzw
 uvec4 t20=uvec4(ivec4(uintBitsToFloat(r2.zzzw)));
 r2.zw=t20.zw;
 // DXBC 21: imax r3.xy, r2.zwzz, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t21=uvec4(max(ivec4(r2.zwzz),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r3.xy=t21.xy;
 // DXBC 22: iadd r3.zw, cb0[155].xxxy, l(0x00000000, 0x00000000, 0xffffffff, 0xffffffff)
 uvec4 t22=(constants[155].xxxy+uvec4(0x00000000u,0x00000000u,0xffffffffu,0xffffffffu));
 r3.zw=t22.zw;
 // DXBC 23: imin r3.xy, r3.zwzz, r3.xyxx
 uvec4 t23=uvec4(min(ivec4(r3.zwzz),ivec4(r3.xyxx)));
 r3.xy=t23.xy;
 // DXBC 24: imad r0.w, r3.y, cb0[155].x, r3.x
 uvec4 t24=(uvec4(r3.y)*uvec4(constants[155].x)+uvec4(r3.x));
 r0.w=t24.w;
 // DXBC 25: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r0.w, l(0x00000000), u0.xyxx
 uvec4 cell25=readCells[(uvec4(r0.w)).x];
 uvec4 t25=uvec4(0u);
 t25.x=cell25.x;
 t25.y=cell25.y;
 r3.xy=t25.xy;
 // DXBC 26: iadd r4.xyzw, r2.zwzw, l(0x00000001, 0x00000000, 0x00000000, 0x00000001)
 uvec4 t26=(r2.zwzw+uvec4(0x00000001u,0x00000000u,0x00000000u,0x00000001u));
 r4.xyzw=t26.xyzw;
 // DXBC 27: iadd r2.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x00000001, 0x00000001)
 uvec4 t27=(r2.zzzw+uvec4(0x00000000u,0x00000000u,0x00000001u,0x00000001u));
 r2.zw=t27.zw;
 // DXBC 28: imax r2.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t28=uvec4(max(ivec4(r2.zzzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r2.zw=t28.zw;
 // DXBC 29: imin r2.zw, r3.zzzw, r2.zzzw
 uvec4 t29=uvec4(min(ivec4(r3.zzzw),ivec4(r2.zzzw)));
 r2.zw=t29.zw;
 // DXBC 30: imad r0.w, r2.w, cb0[155].x, r2.z
 uvec4 t30=(uvec4(r2.w)*uvec4(constants[155].x)+uvec4(r2.z));
 r0.w=t30.w;
 // DXBC 31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r0.w, l(0x00000000), u0.xxxy
 uvec4 cell31=readCells[(uvec4(r0.w)).x];
 uvec4 t31=uvec4(0u);
 t31.z=cell31.x;
 t31.w=cell31.y;
 r2.zw=t31.zw;
 // DXBC 32: imax r4.xyzw, r4.xyzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t32=uvec4(max(ivec4(r4.xyzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r4.xyzw=t32.xyzw;
 // DXBC 33: imin r4.xyzw, r3.zwzw, r4.xyzw
 uvec4 t33=uvec4(min(ivec4(r3.zwzw),ivec4(r4.xyzw)));
 r4.xyzw=t33.xyzw;
 // DXBC 34: imad r3.zw, r4.yyyw, cb0[155].xxxx, r4.xxxz
 uvec4 t34=(r4.yyyw*constants[155].xxxx+r4.xxxz);
 r3.zw=t34.zw;
 // DXBC 35: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xy, r3.z, l(0x00000000), u0.xyxx
 uvec4 cell35=readCells[(uvec4(r3.z)).x];
 uvec4 t35=uvec4(0u);
 t35.x=cell35.x;
 t35.y=cell35.y;
 r4.xy=t35.xy;
 // DXBC 36: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.zw, r3.w, l(0x00000000), u0.xxxy
 uvec4 cell36=readCells[(uvec4(r3.w)).x];
 uvec4 t36=uvec4(0u);
 t36.z=cell36.x;
 t36.w=cell36.y;
 r3.zw=t36.zw;
 // DXBC 37: ushr r4.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x00000010, 0x00000008)
 uvec4 t37=(r2.zzzw>>(uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)&uvec4(31u)));
 r4.zw=t37.zw;
 // DXBC 38: bfi r0.w, l(0x00000010), l(0x00000010), r2.w, r4.z
 uvec4 t38=uvec4(bitfieldInsert((uvec4(r4.z)).x,(uvec4(r2.w)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r4.z)).y,(uvec4(r2.w)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r4.z)).z,(uvec4(r2.w)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r4.z)).w,(uvec4(r2.w)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.w=t38.w;
 // DXBC 39: utof r1.y, r4.w
 precise vec4 f39=vec4(uvec4(r4.w));
 uvec4 t39=floatBitsToUint(f39);
 r1.y=t39.y;
 // DXBC 40: mad r5.y, r1.y, l(0x35000001), l(0xc0800000)
 precise vec4 f40=fma(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t40=floatBitsToUint(f40);
 r5.y=t40.y;
 // DXBC 41: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t41=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t41.w;
 // DXBC 42: utof r0.w, r0.w
 precise vec4 f42=vec4(uvec4(r0.w));
 uvec4 t42=floatBitsToUint(f42);
 r0.w=t42.w;
 // DXBC 43: mad r5.x, r0.w, l(0x35000001), l(0xc0800000)
 precise vec4 f43=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t43=floatBitsToUint(f43);
 r5.x=t43.x;
 // DXBC 44: ushr r2.zw, r3.zzzw, l(0x00000000, 0x00000000, 0x00000010, 0x00000008)
 uvec4 t44=(r3.zzzw>>(uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)&uvec4(31u)));
 r2.zw=t44.zw;
 // DXBC 45: bfi r0.w, l(0x00000010), l(0x00000010), r3.w, r2.z
 uvec4 t45=uvec4(bitfieldInsert((uvec4(r2.z)).x,(uvec4(r3.w)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r2.z)).y,(uvec4(r3.w)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r2.z)).z,(uvec4(r3.w)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r2.z)).w,(uvec4(r3.w)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.w=t45.w;
 // DXBC 46: utof r1.y, r2.w
 precise vec4 f46=vec4(uvec4(r2.w));
 uvec4 t46=floatBitsToUint(f46);
 r1.y=t46.y;
 // DXBC 47: mad r6.y, r1.y, l(0x35000001), l(0xc0800000)
 precise vec4 f47=fma(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t47=floatBitsToUint(f47);
 r6.y=t47.y;
 // DXBC 48: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t48=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t48.w;
 // DXBC 49: utof r0.w, r0.w
 precise vec4 f49=vec4(uvec4(r0.w));
 uvec4 t49=floatBitsToUint(f49);
 r0.w=t49.w;
 // DXBC 50: mad r6.x, r0.w, l(0x35000001), l(0xc0800000)
 precise vec4 f50=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t50=floatBitsToUint(f50);
 r6.x=t50.x;
 // DXBC 51: add r2.zw, r5.xxxy, -r6.xxxy
 precise vec4 f51=(uintBitsToFloat(r5.xxxy)+uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(r6.xxxy))));
 uvec4 t51=floatBitsToUint(f51);
 r2.zw=t51.zw;
 // DXBC 52: mad r2.zw, r0.yyyy, r2.zzzw, r6.xxxy
 precise vec4 f52=fma(uintBitsToFloat(r0.yyyy),uintBitsToFloat(r2.zzzw),uintBitsToFloat(r6.xxxy));
 uvec4 t52=floatBitsToUint(f52);
 r2.zw=t52.zw;
 // DXBC 53: ushr r3.zw, r4.xxxy, l(0x00000000, 0x00000000, 0x00000010, 0x00000008)
 uvec4 t53=(r4.xxxy>>(uvec4(0x00000000u,0x00000000u,0x00000010u,0x00000008u)&uvec4(31u)));
 r3.zw=t53.zw;
 // DXBC 54: bfi r0.w, l(0x00000010), l(0x00000010), r4.y, r3.z
 uvec4 t54=uvec4(bitfieldInsert((uvec4(r3.z)).x,(uvec4(r4.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r3.z)).y,(uvec4(r4.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r3.z)).z,(uvec4(r4.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r3.z)).w,(uvec4(r4.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.w=t54.w;
 // DXBC 55: utof r1.y, r3.w
 precise vec4 f55=vec4(uvec4(r3.w));
 uvec4 t55=floatBitsToUint(f55);
 r1.y=t55.y;
 // DXBC 56: mad r4.y, r1.y, l(0x35000001), l(0xc0800000)
 precise vec4 f56=fma(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t56=floatBitsToUint(f56);
 r4.y=t56.y;
 // DXBC 57: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t57=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t57.w;
 // DXBC 58: utof r0.w, r0.w
 precise vec4 f58=vec4(uvec4(r0.w));
 uvec4 t58=floatBitsToUint(f58);
 r0.w=t58.w;
 // DXBC 59: mad r4.x, r0.w, l(0x35000001), l(0xc0800000)
 precise vec4 f59=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t59=floatBitsToUint(f59);
 r4.x=t59.x;
 // DXBC 60: ushr r3.xz, r3.xxyx, l(0x00000010, 0x00000000, 0x00000008, 0x00000000)
 uvec4 t60=(r3.xxyx>>(uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)&uvec4(31u)));
 r3.xz=t60.xz;
 // DXBC 61: bfi r0.w, l(0x00000010), l(0x00000010), r3.y, r3.x
 uvec4 t61=uvec4(bitfieldInsert((uvec4(r3.x)).x,(uvec4(r3.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r3.x)).y,(uvec4(r3.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r3.x)).z,(uvec4(r3.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r3.x)).w,(uvec4(r3.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r0.w=t61.w;
 // DXBC 62: utof r1.y, r3.z
 precise vec4 f62=vec4(uvec4(r3.z));
 uvec4 t62=floatBitsToUint(f62);
 r1.y=t62.y;
 // DXBC 63: mad r3.y, r1.y, l(0x35000001), l(0xc0800000)
 precise vec4 f63=fma(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t63=floatBitsToUint(f63);
 r3.y=t63.y;
 // DXBC 64: and r0.w, r0.w, l(0x00ffffff)
 uvec4 t64=(uvec4(r0.w)&uvec4(0x00ffffffu));
 r0.w=t64.w;
 // DXBC 65: utof r0.w, r0.w
 precise vec4 f65=vec4(uvec4(r0.w));
 uvec4 t65=floatBitsToUint(f65);
 r0.w=t65.w;
 // DXBC 66: mad r3.x, r0.w, l(0x35000001), l(0xc0800000)
 precise vec4 f66=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t66=floatBitsToUint(f66);
 r3.x=t66.x;
 // DXBC 67: add r3.zw, -r3.xxxy, r4.xxxy
 precise vec4 f67=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(r3.xxxy)))+uintBitsToFloat(r4.xxxy));
 uvec4 t67=floatBitsToUint(f67);
 r3.zw=t67.zw;
 // DXBC 68: mad r0.yw, r0.yyyy, r3.zzzw, r3.xxxy
 precise vec4 f68=fma(uintBitsToFloat(r0.yyyy),uintBitsToFloat(r3.zzzw),uintBitsToFloat(r3.xxxy));
 uvec4 t68=floatBitsToUint(f68);
 r0.yw=t68.yw;
 // DXBC 69: add r2.zw, -r0.yyyw, r2.zzzw
 precise vec4 f69=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(r0.yyyw)))+uintBitsToFloat(r2.zzzw));
 uvec4 t69=floatBitsToUint(f69);
 r2.zw=t69.zw;
 // DXBC 70: mad r0.yz, r0.zzzz, r2.zzwz, r0.yywy
 precise vec4 f70=fma(uintBitsToFloat(r0.zzzz),uintBitsToFloat(r2.zzwz),uintBitsToFloat(r0.yywy));
 uvec4 t70=floatBitsToUint(f70);
 r0.yz=t70.yz;
 // DXBC 71: add r0.yz, r0.yyzy, l(0x00000000, 0x40800000, 0x40800000, 0x00000000)
 precise vec4 f71=(uintBitsToFloat(r0.yyzy)+uintBitsToFloat(uvec4(0x00000000u,0x40800000u,0x40800000u,0x00000000u)));
 uvec4 t71=floatBitsToUint(f71);
 r0.yz=t71.yz;
 // DXBC 72: mul_sat r0.yz, r0.yyzy, l(0x00000000, 0x3e000000, 0x3e000000, 0x00000000)
 precise vec4 f72=clamp((uintBitsToFloat(r0.yyzy)*uintBitsToFloat(uvec4(0x00000000u,0x3e000000u,0x3e000000u,0x00000000u))),vec4(0),vec4(1));
 uvec4 t72=floatBitsToUint(f72);
 r0.yz=t72.yz;
 // DXBC 73: mad r0.yz, r0.yyzy, l(0x00000000, 0x4b7fffff, 0x4b7fffff, 0x00000000), l(0x00000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f73=fma(uintBitsToFloat(r0.yyzy),uintBitsToFloat(uvec4(0x00000000u,0x4b7fffffu,0x4b7fffffu,0x00000000u)),uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t73=floatBitsToUint(f73);
 r0.yz=t73.yz;
 // DXBC 74: ftou r0.yz, r0.yyzy
 uvec4 t74=uvec4(uintBitsToFloat(r0.yyzy));
 r0.yz=t74.yz;
 // DXBC 75: ushr r0.w, r0.y, l(0x00000010)
 uvec4 t75=(uvec4(r0.y)>>(uvec4(0x00000010u)&uvec4(31u)));
 r0.w=t75.w;
 // DXBC 76: ishl r0.z, r0.z, l(0x00000008)
 uvec4 t76=(uvec4(r0.z)<<(uvec4(0x00000008u)&uvec4(31u)));
 r0.z=t76.z;
 // DXBC 77: or r3.y, r0.z, r0.w
 uvec4 t77=(uvec4(r0.z)|uvec4(r0.w));
 r3.y=t77.y;
 // DXBC 78: and r0.zw, r1.xxxz, l(0x00000000, 0x00000000, 0x000000ff, 0x00ffffff)
 uvec4 t78=(r1.xxxz&uvec4(0x00000000u,0x00000000u,0x000000ffu,0x00ffffffu));
 r0.zw=t78.zw;
 // DXBC 79: ubfe r1.xyz, l(0x00000008, 0x00000008, 0x00000004, 0x00000000), l(0x00000008, 0x00000010, 0x00000018, 0x00000000), r1.xwwx
 uvec4 t79=uvec4(bitfieldExtract((r1.xwwx).x,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).x),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).x)),bitfieldExtract((r1.xwwx).y,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).y),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).y)),bitfieldExtract((r1.xwwx).z,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).z),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).z)),bitfieldExtract((r1.xwwx).w,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).w),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).w)));
 r1.xyz=t79.xyz;
 // DXBC 80: utof r1.xyz, r1.xyzx
 precise vec4 f80=vec4(r1.xyzx);
 uvec4 t80=floatBitsToUint(f80);
 r1.xyz=t80.xyz;
 // DXBC 81: mad r1.xyz, r1.xyzx, l(0x3f800000, 0x3f800000, 0x3f800000, 0x00000000), l(0x3f000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f81=fma(uintBitsToFloat(r1.xyzx),uintBitsToFloat(uvec4(0x3f800000u,0x3f800000u,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t81=floatBitsToUint(f81);
 r1.xyz=t81.xyz;
 // DXBC 82: ftou r1.xyz, r1.xyzx
 uvec4 t82=uvec4(uintBitsToFloat(r1.xyzx));
 r1.xyz=t82.xyz;
 // DXBC 83: utof r0.zw, r0.zzzw
 precise vec4 f83=vec4(r0.zzzw);
 uvec4 t83=floatBitsToUint(f83);
 r0.zw=t83.zw;
 // DXBC 84: mad r0.zw, r0.zzzw, l(0x00000000, 0x00000000, 0x3f800000, 0x3f800000), l(0x00000000, 0x00000000, 0x3f000000, 0x3f000000)
 precise vec4 f84=fma(uintBitsToFloat(r0.zzzw),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f800000u,0x3f800000u)),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f000000u,0x3f000000u)));
 uvec4 t84=floatBitsToUint(f84);
 r0.zw=t84.zw;
 // DXBC 85: ftou r4.xy, r0.zwzz
 uvec4 t85=uvec4(uintBitsToFloat(r0.zwzz));
 r4.xy=t85.xy;
 // DXBC 86: imad r0.z, r1.x, l(0x00000100), r4.x
 uvec4 t86=(uvec4(r1.x)*uvec4(0x00000100u)+uvec4(r4.x));
 r0.z=t86.z;
 // DXBC 87: bfi r3.x, l(0x00000010), l(0x00000010), r0.y, r0.z
 uvec4 t87=uvec4(bitfieldInsert((uvec4(r0.z)).x,(uvec4(r0.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.z)).y,(uvec4(r0.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.z)).z,(uvec4(r0.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.z)).w,(uvec4(r0.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r3.x=t87.x;
 // DXBC 88: ishl r5.x, r2.x, l(0x00000018)
 uvec4 t88=(uvec4(r2.x)<<(uvec4(0x00000018u)&uvec4(31u)));
 r5.x=t88.x;
 // DXBC 89: ushr r5.y, r2.x, l(0x00000008)
 uvec4 t89=(uvec4(r2.x)>>(uvec4(0x00000008u)&uvec4(31u)));
 r5.y=t89.y;
 // DXBC 90: ishl r2.w, r2.y, l(0x0000001c)
 uvec4 t90=(uvec4(r2.y)<<(uvec4(0x0000001cu)&uvec4(31u)));
 r2.w=t90.w;
 // DXBC 91: mov r4.z, l(0x00000000)
 uvec4 t91=uvec4(0x00000000u);
 r4.z=t91.z;
 // DXBC 92: iadd r0.yz, r4.yyzy, r5.xxyx
 uvec4 t92=(r4.yyzy+r5.xxyx);
 r0.yz=t92.yz;
 // DXBC 93: imad r0.z, r1.y, l(0x00010000), r0.z
 uvec4 t93=(uvec4(r1.y)*uvec4(0x00010000u)+uvec4(r0.z));
 r0.z=t93.z;
 // DXBC 94: mov r3.z, r0.y
 uvec4 t94=uvec4(r0.y);
 r3.z=t94.z;
 // DXBC 95: imad r3.w, r1.z, l(0x01000000), r0.z
 uvec4 t95=(uvec4(r1.z)*uvec4(0x01000000u)+uvec4(r0.z));
 r3.w=t95.w;
 // DXBC 96: mov r2.xyz, l(0x00000000,0x00000000,0x00000000,0x00000000)
 uvec4 t96=uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u);
 r2.xyz=t96.xyz;
 // DXBC 97: iadd r1.xyzw, r2.xyzw, r3.xyzw
 uvec4 t97=(r2.xyzw+r3.xyzw);
 r1.xyzw=t97.xyzw;
 // DXBC 98: store_structured u0.xyzw, r0.x, l(0x00000000), r1.xyzw
 uvec4 t98=r1.xyzw;
 waterCells[(uvec4(r0.x)).x]=t98;
 // DXBC 99: ret
 return;
}
