#[compute]
#version 450
// Topology/CSR phase copied from the verified packed algorithm. Math runs in separate dispatches.
layout(local_size_x=64) in;
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) buffer Candidate { vec4 output_cells[]; };
layout(set=0,binding=2,std430) buffer Scratch { int labels[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint receipt[]; };
layout(push_constant,std430) uniform Params { uint size; float cell_size; uint pad0; uint pad1; } params;
// Private phase handoff; no authority fields or CPU round trip.
struct Component { uvec4 span; vec4 surface; vec4 totals; vec4 flow; vec4 audit; uvec4 repair; };
layout(set=0,binding=4,std430) buffer Components { uvec4 state; Component components[]; };
shared uint bad,wet_count,component_count,has_demand;
shared uint starts[32];
// At most eight horizontal wet runs per row, <=256 rows. Shared footprint <32KiB.
shared uint runs[2048], ranks[2048], sizes[2048], row_count[256];
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
uint count,lane;
bool finite(float x) { return !isnan(x)&&!isinf(x); }
bool wet(vec4 a,vec4 b) { return a.z>0.001&&b.z<0.5; }
vec4 before(uint j) { return vec4(input_cells[j].bed_water.zw,input_cells[j].flow.xy); }
void main() {
    count=params.size*params.size;lane=gl_LocalInvocationID.x;
    if(params.size>256u||params.size<1u) { if(lane==0u) receipt[27]=0u;return; }
    if(lane==0u) { state=uvec4(0u);bad=0u;wet_count=0u;component_count=0u;has_demand=0u;receipt[27]=0u; } barrier();
    for(uint j=lane;j<2048u;j+=64u) { runs[j]=(j<<16u);ranks[j]=0u;sizes[j]=0u; }
    for(uint j=lane;j<count;j+=64u) {
        vec4 a=input_cells[j].bed_water,b=input_cells[j].flow;
        if(!finite(a.x)||!finite(a.y)||!finite(a.z)||!finite(a.w)||!finite(b.x)||!finite(b.y)||!finite(b.z)||a.z<0.0||a.w<0.0) atomicOr(bad,1u);
        if(wet(a,b)&&a.y>a.x) atomicOr(has_demand,1u);
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
            for(uint x=packed_run&255u;x<=(packed_run>>8u);x++) labels[row*params.size+x]=int(rank);
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
    } barrier();
    if(lane<component_count) {
        Component c;
        c.span=uvec4(starts[lane],sizes[lane],0u,0u);
        c.surface=vec4(0.0);c.totals=vec4(0.0);c.flow=vec4(0.0);
        c.audit=vec4(0.0);c.repair=uvec4(0u);components[lane]=c;
    }
    if(lane==0u) {
        state=uvec4(has_demand!=0u?component_count:0u,component_count,count,0u);
        receipt[0]=1u;
    }
}
