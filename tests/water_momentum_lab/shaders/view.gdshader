shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D state:filter_nearest,repeat_disable;
uniform int view_mode=0;
uniform bool water_layer=false;
uniform bool arrows=true;
varying vec2 uv;
void vertex(){uv=UV;vec4 s=texture(state,UV);VERTEX.y=s.x+(water_layer?s.y:0.);}
void fragment(){
 vec4 s=texture(state,uv);vec2 v=s.y>.001?s.zw/s.y:vec2(0);float speed=length(v);
 vec3 sand=mix(vec3(.31,.21,.10),vec3(.78,.64,.38),clamp(s.x,0.,1.));
 vec3 color=sand;
 if(water_layer){if(s.y<=.001)discard;color=mix(sand,vec3(.04,.37,.57),clamp(s.y*1.5,.1,.85));}
 if(view_mode==1)color=mix(vec3(.07,.12,.19),vec3(.05,.77,1.),clamp(s.y*2.,0.,1.));
 if(view_mode==2)color=mix(vec3(.035,.07,.12),vec3(1.,.42,.08),clamp(speed,0.,1.));
 if(view_mode==3)color=sand;
 if(arrows&&water_layer&&speed>.015){
  vec2 g=fract(uv*24.)-.5,dir=v/max(speed,.0001);vec2 r=vec2(dot(g,dir),dot(g,vec2(-dir.y,dir.x)));
  bool shaft=abs(r.y)<.025&&abs(r.x)<.27;
  bool head=r.x>.05&&r.x<.28&&abs(abs(r.y)-(.28-r.x))<.035;
  if(shaft||head)color=vec3(.90,.98,1.);
 }
 ALBEDO=color;
}
