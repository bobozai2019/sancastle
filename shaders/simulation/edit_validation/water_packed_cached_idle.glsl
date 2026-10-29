#[compute]
#version 450
layout(local_size_x=64) in;
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) buffer Candidate { vec4 output_cells[]; };
layout(set=0,binding=2,std430) buffer Scratch { int labels[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint receipt[]; };
layout(push_constant,std430) uniform Params { uint size; float cell_size; uint pad0; uint pad1; } params;
shared vec4 v[64], f[64], o[64];
shared vec2 dry_loss[64];
shared uint bad,wet_count,component_count,current_component;
shared uint starts[32],cell_ids[64];
shared uint raised_components;
// At most eight horizontal wet runs per row, <=256 rows. Shared footprint <32KiB.
shared uint runs[2048], ranks[2048], sizes[2048], row_count[256];
shared precise float total_moved,tmc,total_retained,trc;
uint run_root(uint node) {
    uint next=atomicAdd(runs[node],0u)>>16u;
    while(next!=node) { node=next;next=atomicAdd(runs[node],0u)>>16u; }
    return node;
}
void unite(uint a,uint b) {
    for(;;) {
        a=run_root(a);b=run_root(b);if(a==b) return;
        uint hi=max(a,b),lo=min(a,b);
        uint payload=atomicAdd(runs[hi],0u)&65535u;
        uint old=atomicCompSwap(runs[hi],(hi<<16u)|payload,(lo<<16u)|payload);
        if((old>>16u)==hi) return;
    }
}
bool selected(uint index,vec4 a,vec4 b,uint component) {
    return a.z>0.001&&b.z<0.5; // packed entries belong to this component; padding is dry
}
shared precise vec2 eta_pair;
shared precise vec2 surface_pair[64];
shared precise float receiver_room[64];
// Error-free two-sum plus renormalization; no fp64 or contract change.
vec2 pair_add(vec2 a, float b) {
    precise float sum=a.x+b;
    precise float z=sum-a.x;
    precise float error=(a.x-(sum-z))+(b-z);
    precise float tail=a.y+error;
    precise float hi=sum+tail;
    precise float lo=tail-(hi-sum);
    return vec2(hi,lo);
}
float ceiling(float bed) {
    vec2 value=pair_add(eta_pair,-bed);
    precise float result=value.x+value.y;
    return result;
}
float room_depth(vec4 v) {
    vec2 value=pair_add(pair_add(eta_pair,-v.y),-v.z);
    precise float result=value.x+value.y;
    return max(0.0,result);
}
shared precise float demand,dc,capacity,cc,actual,ac,sed,sc,qx,qxc,qz,qzc,loss_x,lxc,loss_z,lzc;
shared precise float residual,ec,wquant,wqc,squant,sqc,wabs,wac,sabs,sac,serror,sec;
uint count,lane; float area;
void add(inout float sum,inout float correction,float x) {
    precise float y=x-correction; precise float next=sum+y;
    correction=(next-sum)-y;sum=next;
}
bool finite(float x) { return !isnan(x)&&!isinf(x); }
bool wet(vec4 a,vec4 b) { return a.z>0.001&&b.z<0.5; }
float ulp(float x) { uint e=(floatBitsToUint(abs(x))>>23u)&255u;return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23)); }
vec4 before(uint j) { return vec4(input_cells[j].bed_water.zw,input_cells[j].flow.xy); }
void load_tile(uint base) {
    bool valid=base+lane<wet_count;
    uint index=valid?uint(labels[count+starts[current_component]+base+lane]):0u;
    cell_ids[lane]=index;
    v[lane]=valid?input_cells[index].bed_water:vec4(0.0);
    f[lane]=valid?input_cells[index].flow:vec4(0.0);
    o[lane]=valid?output_cells[index]:vec4(0.0);barrier();
}
void main() {
    count=params.size*params.size;lane=gl_LocalInvocationID.x;area=params.cell_size*params.cell_size;
    if(params.size>256u||params.size<1u) { if(lane==0u) receipt[27]=0u;return; }
    if(lane==0u) { bad=0u;wet_count=0u;component_count=0u;receipt[27]=0u;raised_components=0u; } barrier();
    for(uint j=lane;j<2048u;j+=64u) { runs[j]=(j<<16u);ranks[j]=0u;sizes[j]=0u; }
    for(uint j=lane;j<count;j+=64u) {
        vec4 a=input_cells[j].bed_water,b=input_cells[j].flow;
        if(!finite(a.x)||!finite(a.y)||!finite(a.z)||!finite(a.w)||!finite(b.x)||!finite(b.y)||!finite(b.z)||a.z<0.0||a.w<0.0) atomicOr(bad,1u);
    }
    for(uint row=lane;row<params.size;row+=64u) {
        uint members=0u,start=0u,number=0u;bool in_run=false;
        for(uint x=0u;x<=params.size;x++) {
            bool w=false;
            if(x<params.size) w=wet(input_cells[row*params.size+x].bed_water,input_cells[row*params.size+x].flow);
            if(w&&!in_run) { start=x;in_run=true; }
            if(!w&&in_run) {
                if(number<8u) { uint node=row*8u+number;runs[node]=(node<<16u)|((x-1u)<<8u)|start; }
                else atomicOr(bad,1u);
                number++;in_run=false;
            }
            if(w) members++;
        }
        row_count[row]=number;atomicAdd(wet_count,members);
    }
    barrier();if(bad!=0u||wet_count==0u) return;
    // A wet run is horizontally connected. Overlapping runs in neighboring
    // rows have a vertical edge. DSU therefore equals the original 4-neighbor graph.
    for(uint row=lane;row<params.size;row+=64u) if(row>0u) {
        for(uint k=0u;k<row_count[row];k++) {
            uint a=row*8u+k,packed_a=atomicAdd(runs[a],0u)&65535u;
            for(uint j=0u;j<row_count[row-1u];j++) {
                uint b=(row-1u)*8u+j,packed_b=atomicAdd(runs[b],0u)&65535u;
                if(max(packed_a&255u,packed_b&255u)<=min(packed_a>>8u,packed_b>>8u)) unite(a,b);
            }
        }
    }
    barrier();
    for(uint row=lane;row<params.size;row+=64u) for(uint k=0u;k<row_count[row];k++) {
        uint node=row*8u+k,root=run_root(node),packed_run=runs[node]&65535u;
        atomicAdd(sizes[root],(packed_run>>8u)-(packed_run&255u)+1u);
    }
    barrier();
    if(lane==0u) {
        for(uint row=0u;row<params.size;row++) for(uint k=0u;k<row_count[row];k++) {
            uint node=row*8u+k;
            if(run_root(node)==node) { ranks[node]=component_count;sizes[component_count]=sizes[node];component_count++; }
        }
    }
    barrier();
    if(component_count>min(32u,params.size)) return; // bounded CSR metadata, original BFS otherwise
    for(uint row=lane;row<params.size;row+=64u) {
        for(uint x=0u;x<params.size;x++) { labels[row*params.size+x]=-1;output_cells[row*params.size+x]=before(row*params.size+x); }
        for(uint k=0u;k<row_count[row];k++) {
            uint node=row*8u+k,packed_run=runs[node]&65535u,rank=ranks[run_root(node)];
            for(uint x=packed_run&255u;x<=(packed_run>>8u);x++) {
                uint index=row*params.size+x;labels[index]=int(rank);
                vec4 value=input_cells[index].bed_water;
                if(value.y>value.x) atomicOr(raised_components,1u<<rank);
            }
        }
    }
    memoryBarrierBuffer();barrier();
    // Row counts/prefixes occupy scratch segment 2; packed indices segment 1.
    for(uint j=lane;j<component_count*params.size;j+=64u) labels[2u*count+j]=0;
    memoryBarrierBuffer();barrier();
    for(uint row=lane;row<params.size;row+=64u) for(uint k=0u;k<row_count[row];k++) {
        uint node=row*8u+k,packed_run=runs[node]&65535u,rank=ranks[run_root(node)];
        labels[2u*count+rank*params.size+row]+=int((packed_run>>8u)-(packed_run&255u)+1u);
    }
    memoryBarrierBuffer();barrier();
    if(lane==0u) {
        uint offset=0u;
        for(uint component=0u;component<component_count;component++) {
            starts[component]=offset;
            for(uint row=0u;row<params.size;row++) {
                uint slot=2u*count+component*params.size+row;
                uint amount=uint(labels[slot]);labels[slot]=int(offset);offset+=amount;
            }
        }
    }
    memoryBarrierBuffer();barrier();
    for(uint row=lane;row<params.size;row+=64u) for(uint x=0u;x<params.size;x++) {
        uint index=row*params.size+x;int rank=labels[index];
        if(rank>=0) {
            uint slot=2u*count+uint(rank)*params.size+row;
            uint offset=uint(labels[slot]);labels[slot]++;
            labels[count+offset]=int(index);
        }
    }
    memoryBarrierBuffer();barrier();
    if(lane==0u) {
        for(uint j=0u;j<32u;j++) receipt[j]=0u;
        receipt[27]=1u;receipt[2]=component_count;
        for(uint j=0u;j<component_count;j++) receipt[11]=max(receipt[11],sizes[j]);
        total_moved=0.0;tmc=0.0;total_retained=0.0;trc=0.0;
        loss_x=0.0;lxc=0.0;loss_z=0.0;lzc=0.0;
    } barrier();
    for(uint component=0u;component<component_count;component++) {
        // No raised wet bed guarantees the original demand is exactly zero.
        // Preserve component statistics, initialized output and all active arithmetic.
        if((raised_components&(1u<<component))==0u) continue;
        if(lane==0u) {
            current_component=component;wet_count=sizes[component];eta_pair=vec2(-3.402823466e38,0.0);
            demand=0.0;dc=0.0;capacity=0.0;cc=0.0;
            actual=0.0;ac=0.0;sed=0.0;sc=0.0;qx=0.0;qxc=0.0;qz=0.0;qzc=0.0;
        } barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        surface_pair[lane]=pair_add(vec2(v[lane].x,0.0),v[lane].z);barrier();
        if(lane==0u) for(uint k=0u;k<64u;k++) if(selected(cell_ids[k],v[k],f[k],component)) {
            vec2 surface=surface_pair[k];
            if(surface.x>eta_pair.x||(surface.x==eta_pair.x&&surface.y>eta_pair.y)) eta_pair=surface;
        }
        barrier();
    }
    if(lane==0u) eta_pair=pair_add(eta_pair,0.02);barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        receiver_room[lane]=0.0;
        if(base+lane<wet_count&&v[lane].y<=v[lane].x) {
            receiver_room[lane]=room_depth(v[lane]);
            // Scratch segment 3 is unused by packed CSR; native float bits persist.
            labels[3u*count+cell_ids[lane]]=int(floatBitsToUint(receiver_room[lane]));
        }
        memoryBarrierBuffer();barrier();
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!selected(cell_ids[k],v[k],f[k],component)) continue;
            if(v[k].y>v[k].x) add(demand,dc,min(v[k].z,max(0.0,v[k].y-v[k].x))*area);
            else add(capacity,cc,receiver_room[k]*area);
        } barrier();
    }
    if(demand==0.0) continue;
    if(lane==0u&&capacity<demand) receipt[3]=1u;barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        vec4 old=vec4(v[lane].zw,f[lane].xy);
        precise vec4 result=o[lane]; // preserve completed earlier components; current component starts at old
        float dry_x=0.0,dry_z=0.0;
        if(selected(cell_ids[lane],v[lane],f[lane],component)&&v[lane].y>v[lane].x) {
            float fraction=min(demand,capacity)/demand;
            result.x=max(0.0,old.x-min(v[lane].z,max(0.0,v[lane].y-v[lane].x))*fraction);
            float depth=old.x-result.x,proportion=clamp(depth/old.x,0.0,1.0);
            result.yzw=old.yzw*(1.0-proportion);
            if(result.x<=0.001) { dry_x=result.z;dry_z=result.w;result.zw=vec2(0.0); }
        }
        o[lane]=result;dry_loss[lane]=vec2(dry_x,dry_z);barrier();
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!selected(cell_ids[k],v[k],f[k],component)||v[k].y<=v[k].x) continue;
            vec4 b=vec4(v[k].zw,f[k].xy),r=o[k];
            if(r.x<=0.001) { add(loss_x,lxc,dry_loss[k].x*area);add(loss_z,lzc,dry_loss[k].y*area); }
            add(actual,ac,(b.x-r.x)*area);add(sed,sc,(b.y-r.y)*area);
            add(qx,qxc,(b.z-r.z-dry_loss[k].x)*area);add(qz,qzc,(b.w-r.w-dry_loss[k].y)*area);
        } barrier();if(base+lane<wet_count) output_cells[cell_ids[lane]]=o[lane];memoryBarrierBuffer();barrier();
    }
    for(uint slot=lane;slot<wet_count;slot+=64u) {
        uint j=uint(labels[count+starts[component]+slot]);
        vec4 a=input_cells[j].bed_water;
        if(a.y<=a.x&&capacity>0.0) {
            float room=uintBitsToFloat(uint(labels[3u*count+j]))*area,share=room/capacity;
            output_cells[j]+=vec4(actual,sed,qx,qz)*share/area;
        }
        if(params.pad0==1u) output_cells[j].x=0.0;
    } memoryBarrierBuffer();barrier();
    if(lane==0u) { residual=0.0;ec=0.0; } barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) if(selected(cell_ids[k],v[k],f[k],component)) add(residual,ec,(o[k].x-v[k].z)*area);
        barrier();
    }
    if(lane==0u) receipt[14]=floatBitsToUint(max(uintBitsToFloat(receipt[14]),abs(residual)));barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u&&abs(residual)>1e-8;k++) {
            if(!selected(cell_ids[k],v[k],f[k],component)||v[k].y>v[k].x) continue;
            float old=o[k].x,limit=max(1e-7,8.0*ulp(max(abs(v[k].z),abs(old))));
            float step=clamp(-residual/area,-limit,limit);
            float corrected=clamp(old+step,v[k].z,max(v[k].z,ceiling(v[k].y)));
            o[k].x=corrected;residual+=(corrected-old)*area;
            if(corrected!=old) receipt[15]++;
            receipt[16]=floatBitsToUint(max(uintBitsToFloat(receipt[16]),abs(corrected-old)));
        } barrier();if(base+lane<wet_count) output_cells[cell_ids[lane]]=o[lane];memoryBarrierBuffer();barrier();
    }
    if(lane==0u) { wquant=0.0;wqc=0.0;squant=0.0;sqc=0.0;wabs=0.0;wac=0.0;sabs=0.0;sac=0.0;serror=0.0;sec=0.0;bad=0u; } barrier();
    for(uint base=0u;base<wet_count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!selected(cell_ids[k],v[k],f[k],component)) continue;
            vec4 b=vec4(v[k].zw,f[k].xy),r=o[k];
            if(!finite(r.x)||!finite(r.y)||!finite(r.z)||!finite(r.w)||r.x<0.0||r.y<0.0) bad=1u;
            add(wquant,wqc,2.0*ulp(max(abs(b.x),abs(r.x)))*area);
            add(squant,sqc,2.0*ulp(max(abs(b.y),abs(r.y)))*area);
            add(wabs,wac,abs(r.x-b.x)*area);add(sabs,sac,abs(r.y-b.y)*area);add(serror,sec,(r.y-b.y)*area);
        } barrier();
    }
    if(lane==0u) {
        float u=5.9604644775390625e-8;
        float wb=max(1e-7,wquant+max(1e-8,(4.0*u+2.0*float(wet_count)*u*u)*wabs));
        float sb=max(1e-7,squant+max(1e-8,(4.0*u+2.0*float(wet_count)*u*u)*sabs));
        receipt[8]=floatBitsToUint(max(uintBitsToFloat(receipt[8]),abs(residual)));receipt[9]=floatBitsToUint(max(uintBitsToFloat(receipt[9]),abs(serror)));receipt[12]=floatBitsToUint(max(uintBitsToFloat(receipt[12]),wb));
        if(abs(residual)>wb||abs(serror)>sb) bad=1u;
        if(bad!=0u) { receipt[0]=2u;receipt[1]=4u; }
        else { add(total_moved,tmc,actual);add(total_retained,trc,max(0.0,demand-actual)); }
    } barrier();
    if(bad!=0u) { if(lane==0u) receipt[27]=0u;return; } // original BFS reproduces rejection diagnostics
    } // components, in original first-cell order
    if(lane==0u) {
        receipt[0]=1u;receipt[4]=floatBitsToUint(total_moved);receipt[5]=floatBitsToUint(total_retained);
        receipt[6]=floatBitsToUint(loss_x);receipt[7]=floatBitsToUint(loss_z);
    }
}
