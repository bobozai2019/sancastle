shader_type canvas_item;
uniform sampler2D sand_state: filter_nearest;
uniform sampler2D water_state: filter_nearest;
uniform sampler2D compaction_state: filter_nearest;
uniform sampler2D wetness_state: filter_nearest;
uniform sampler2D sediment_state: filter_nearest;
uniform sampler2D qx_state: filter_nearest;
uniform sampler2D rock_state: filter_nearest;
uniform sampler2D stroke_baseline: filter_nearest;
uniform sampler2D async_clock: filter_nearest;
uniform ivec2 cell = ivec2(192, 128);
uniform int mode = 0;
void fragment(){
 if(mode==0)COLOR=vec4(texelFetch(sand_state,cell,0).r,texelFetch(water_state,cell,0).r,texelFetch(compaction_state,cell,0).r,1);
 else if(mode==1)COLOR=vec4(texelFetch(sediment_state,cell,0).r,texelFetch(qx_state,cell,0).r+0.5,texelFetch(wetness_state,cell,0).r,1);
 else COLOR=vec4(texelFetch(rock_state,cell,0).r,texelFetch(stroke_baseline,cell,0).r,texelFetch(async_clock,ivec2(0),0).r,1);
}
