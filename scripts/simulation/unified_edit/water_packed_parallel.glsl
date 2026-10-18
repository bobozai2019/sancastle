#[compute]
#version 450
// Per-cell phases use 1024 groups. Ordered reductions use one group per
// component, preserving the original CSR row order and compensated additions.
layout(local_size_x=64) in;
layout(constant_id=0) const uint MODE=0u;
struct InputCell { vec4 bed_water; vec4 flow; };
struct Component { uvec4 span; vec4 surface; vec4 totals; vec4 flow; vec4 audit; uvec4 repair; };
struct CellWork { vec4 a; vec4 b; vec4 c; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) buffer Candidate { vec4 output_cells[]; };
layout(set=0,binding=2,std430) buffer Scratch { int labels[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint receipt[]; };
layout(set=0,binding=4,std430) buffer Components { uvec4 state; Component components[]; };
layout(set=0,binding=5,std430) buffer Work { CellWork work[]; };
layout(push_constant,std430) uniform Params { uint size; float cell_size; uint mode; uint unused; } params;
const uint TILE=512u;
shared vec4 a[512],b[512],c[512];
shared uint ids[64];
shared precise float s0,s1,s2,s3,s4,s5,e0,e1,e2,e3,e4,e5;
shared uint bad;
shared precise float sums[5];
uint lane,count;
float area;

vec2 pair_add(vec2 a,float b) {
    precise float sum=a.x+b;
    precise float z=sum-a.x;
    precise float error=(a.x-(sum-z))+(b-z);
    precise float tail=a.y+error;
    precise float hi=sum+tail;
    precise float lo=tail-(hi-sum);
    return vec2(hi,lo);
}
void add(inout float sum,inout float correction,float x) {
    precise float y=x-correction;
    precise float next=sum+y;
    correction=(next-sum)-y;sum=next;
}
bool finite(float x) { return !isnan(x)&&!isinf(x); }
float ulp(float x) {
    uint e=(floatBitsToUint(abs(x))>>23u)&255u;
    return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23));
}
bool greater_pair(vec2 x,vec2 y) { return x.x>y.x||(x.x==y.x&&x.y>y.y); }
void clear_sums() {
    if(lane==0u) { s0=0.0;s1=0.0;s2=0.0;s3=0.0;s4=0.0;s5=0.0;e0=0.0;e1=0.0;e2=0.0;e3=0.0;e4=0.0;e5=0.0;bad=0u; }
    barrier();
}
void load_work(uvec4 span,uint base) {
    for(uint k=lane;k<TILE;k+=64u) {
        bool valid=base+k<span.y;
        uint i=valid?uint(labels[count+span.x+base+k]):0u;
        a[k]=valid?work[i].a:vec4(0.0);
        b[k]=valid?work[i].b:vec4(0.0);
        c[k]=valid?work[i].c:vec4(0.0);
    }
    barrier();
}

void per_cell(uint i) {
    int rank=labels[i];if(rank<0) return;
    Component comp=components[rank];
    vec4 v=input_cells[i].bed_water,f=input_cells[i].flow;
    if(MODE==1u) {
        float room=0.0;
        if(v.y<=v.x) {
            vec2 pair=pair_add(pair_add(comp.surface.xy,-v.y),-v.z);
            precise float depth=pair.x+pair.y;
            room=max(0.0,depth);
            labels[3u*count+i]=int(floatBitsToUint(room));
        }
        work[i].a=vec4(min(v.z,max(0.0,v.y-v.x))*area,room*area,v.y>v.x?1.0:0.0,0.0);
        work[i].b=vec4(0.0);work[i].c=vec4(0.0);
        return;
    }
    if(comp.totals.x==0.0) return;
    if(MODE==3u) {
        vec4 old=vec4(v.zw,f.xy);
        precise vec4 result=output_cells[i];
        float dry_x=0.0,dry_z=0.0;
        bool donor=v.y>v.x;
        if(donor) {
            float fraction=min(comp.totals.x,comp.totals.y)/comp.totals.x;
            result.x=max(0.0,old.x-min(v.z,max(0.0,v.y-v.x))*fraction);
            float depth=old.x-result.x,proportion=clamp(depth/old.x,0.0,1.0);
            result.yzw=old.yzw*(1.0-proportion);
            if(result.x<=0.001) { dry_x=result.z;dry_z=result.w;result.zw=vec2(0.0); }
        }
        output_cells[i]=result;
        work[i].a=vec4((old.x-result.x)*area,(old.y-result.y)*area,(old.z-result.z-dry_x)*area,(old.w-result.w-dry_z)*area);
        work[i].b=vec4(dry_x*area,dry_z*area,donor&&result.x<=0.001?1.0:0.0,donor?1.0:0.0);
        if(donor&&result.x<=0.001) atomicOr(components[rank].span.z,1u);
    } else if(MODE==5u) {
        if(v.y<=v.x&&comp.totals.y>0.0) {
            float room=uintBitsToFloat(uint(labels[3u*count+i]))*area,share=room/comp.totals.y;
            output_cells[i]+=vec4(comp.totals.zw,comp.flow.xy)*share/area;
        }
    } else if(MODE==8u) {
        vec4 old=vec4(v.zw,f.xy),r=output_cells[i];
        work[i].a=vec4(2.0*ulp(max(abs(old.x),abs(r.x)))*area,2.0*ulp(max(abs(old.y),abs(r.y)))*area,abs(r.x-old.x)*area,abs(r.y-old.y)*area);
        work[i].c=vec4((r.y-old.y)*area,(!finite(r.x)||!finite(r.y)||!finite(r.z)||!finite(r.w)||r.x<0.0||r.y<0.0)?1.0:0.0,0.0,0.0);
    }
}

void component_phase(uint rank) {
    Component comp=components[rank];
    uvec4 span=comp.span;
    if(MODE==0u) {
        vec2 best=vec2(-3.402823466e38,0.0);
        for(uint slot=lane;slot<span.y;slot+=64u) {
            uint i=uint(labels[count+span.x+slot]);vec4 v=input_cells[i].bed_water;
            vec2 surface=pair_add(vec2(v.x,0.0),v.z);
            if(greater_pair(surface,best)) best=surface;
        }
        a[lane]=vec4(best,0.0,0.0);barrier();
        for(uint step=32u;step>0u;step>>=1u) {
            if(lane<step&&greater_pair(a[lane+step].xy,a[lane].xy)) a[lane].xy=a[lane+step].xy;
            barrier();
        }
        if(lane==0u) components[rank].surface=vec4(pair_add(a[0].xy,0.02),0.0,0.0);
        return;
    }
    if(MODE!=2u&&comp.totals.x==0.0) return;
    clear_sums();
    if(MODE==2u||MODE==4u||MODE==9u) {
        // One lane per independent ledger preserves every original addition
        // sequence while evaluating up to five ledgers simultaneously.
        precise float sum=0.0,correction=0.0;
        uint ledgers=MODE==2u?2u:(MODE==4u?4u:5u);
        for(uint base=0u;base<span.y;base+=TILE) {
            load_work(span,base);
            if(MODE==9u) for(uint k=lane;k<TILE;k+=64u) if(c[k].y!=0.0) atomicOr(bad,1u);
            if(lane<ledgers) for(uint k=0u;k<min(TILE,span.y-base);k++) {
                if(MODE==2u) {
                    if((a[k].z!=0.0)==(lane==0u)) add(sum,correction,a[k][lane]);
                } else if(MODE==4u) {
                    if(b[k].w!=0.0) add(sum,correction,a[k][lane]);
                } else add(sum,correction,lane<4u?a[k][lane]:c[k].x);
            }
            barrier();
        }
        if(lane<ledgers) sums[lane]=sum;
        barrier();
        if(lane==0u) { s0=sums[0];s1=sums[1];if(ledgers>2u) {s2=sums[2];s3=sums[3];}if(ledgers>4u)s4=sums[4]; }
        barrier();
        if(lane==0u) {
            if(MODE==2u) components[rank].totals.xy=vec2(s0,s1);
            else if(MODE==4u) { components[rank].totals.zw=vec2(s0,s1);components[rank].flow.xy=vec2(s2,s3); }
            else {
                // Same binary32 unit roundoff and frozen budget as the reference.
                float u=5.9604644775390625e-8;
                float wb=max(1e-7,s0+max(1e-8,(4.0*u+2.0*float(span.y)*u*u)*s2));
                float sb=max(1e-7,s1+max(1e-8,(4.0*u+2.0*float(span.y)*u*u)*s3));
                components[rank].audit.yzw=vec3(s4,wb,sb);
                components[rank].span.w=(bad!=0u||abs(comp.audit.x)>wb||abs(s4)>sb)?1u:0u;
            }
        }
    } else if(MODE==6u) {
        for(uint base=0u;base<span.y;base+=TILE) {
            for(uint k=lane;k<TILE;k+=64u) {
                bool valid=base+k<span.y;
                uint i=valid?uint(labels[count+span.x+base+k]):0u;
                a[k].x=valid?(output_cells[i].x-input_cells[i].bed_water.z)*area:0.0;
            }
            barrier();
            if(lane==0u) for(uint k=0u;k<min(TILE,span.y-base);k++) add(s0,e0,a[k].x);
            barrier();
        }
        if(lane==0u) { components[rank].audit.x=s0;components[rank].repair.z=floatBitsToUint(abs(s0)); }
    } else if(MODE==7u) {
        if(lane==0u) s0=comp.audit.x;barrier();
        for(uint base=0u;base<span.y&&abs(s0)>1e-8;base+=64u) {
            bool valid=base+lane<span.y;
            uint i=valid?uint(labels[count+span.x+base+lane]):0u;
            ids[lane]=i;a[lane]=valid?input_cells[i].bed_water:vec4(0.0);
            b[lane]=valid?output_cells[i]:vec4(0.0);barrier();
            if(lane==0u) for(uint k=0u;k<min(64u,span.y-base)&&abs(s0)>1e-8;k++) {
                if(a[k].y>a[k].x) continue;
                float old=b[k].x,limit=max(1e-7,8.0*ulp(max(abs(a[k].z),abs(old))));
                float step=clamp(-s0/area,-limit,limit);
                vec2 ceiling_pair=pair_add(comp.surface.xy,-a[k].y);
                precise float ceiling=ceiling_pair.x+ceiling_pair.y;
                float corrected=clamp(old+step,a[k].z,max(a[k].z,ceiling));
                b[k].x=corrected;s0+=(corrected-old)*area;
                if(corrected!=old) comp.repair.x++;
                comp.repair.y=floatBitsToUint(max(uintBitsToFloat(comp.repair.y),abs(corrected-old)));
            }
            barrier();if(valid) output_cells[ids[lane]]=b[lane];memoryBarrierBuffer();barrier();
        }
        if(lane==0u) { components[rank].audit.x=s0;components[rank].repair=comp.repair; }
    }
}

void finish_response() {
    clear_sums();
    // Loss ledger also retains the original component/row order, including
    // zero terms. Do not merge independently rounded component totals.
    for(uint rank=0u;rank<state.x;rank++) {
        Component comp=components[rank];if(comp.totals.x==0.0) continue;
        if(comp.span.z!=0u) for(uint base=0u;base<comp.span.y;base+=TILE) {
            for(uint k=lane;k<TILE;k+=64u) {
                bool valid=base+k<comp.span.y;
                uint i=valid?uint(labels[count+comp.span.x+base+k]):0u;
                b[k]=valid?work[i].b:vec4(0.0);
            }
            barrier();
            if(lane==0u) for(uint k=0u;k<min(TILE,comp.span.y-base);k++) if(b[k].z!=0.0) { add(s0,e0,b[k].x);add(s1,e1,b[k].y); }
            barrier();
        }
        if(lane==0u) {
            if(comp.totals.y<comp.totals.x) receipt[3]=1u;
            receipt[8]=floatBitsToUint(max(uintBitsToFloat(receipt[8]),abs(comp.audit.x)));
            receipt[9]=floatBitsToUint(max(uintBitsToFloat(receipt[9]),abs(comp.audit.y)));
            receipt[12]=floatBitsToUint(max(uintBitsToFloat(receipt[12]),comp.audit.z));
            receipt[14]=floatBitsToUint(max(uintBitsToFloat(receipt[14]),uintBitsToFloat(comp.repair.z)));
            receipt[15]+=comp.repair.x;
            receipt[16]=floatBitsToUint(max(uintBitsToFloat(receipt[16]),uintBitsToFloat(comp.repair.y)));
            if(comp.span.w!=0u) { receipt[0]=2u;receipt[1]=4u;receipt[27]=0u;bad=1u; }
            else { add(s2,e2,comp.totals.z);add(s3,e3,max(0.0,comp.totals.x-comp.totals.z)); }
        }
        barrier();if(bad!=0u) return;
    }
    if(lane==0u) {
        receipt[0]=1u;receipt[4]=floatBitsToUint(s2);receipt[5]=floatBitsToUint(s3);
        receipt[6]=floatBitsToUint(s0);receipt[7]=floatBitsToUint(s1);
    }
}

void main() {
    if(receipt[27]!=1u||state.x==0u) return;
    lane=gl_LocalInvocationID.x;count=params.size*params.size;area=params.cell_size*params.cell_size;
    if(MODE==1u||MODE==3u||MODE==5u||MODE==8u) {
        uint i=gl_GlobalInvocationID.x;if(i<count) per_cell(i);
    } else if(MODE==10u) finish_response();
    else if(gl_WorkGroupID.x<state.x) component_phase(gl_WorkGroupID.x);
}
