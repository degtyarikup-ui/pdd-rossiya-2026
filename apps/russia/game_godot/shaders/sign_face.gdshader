// One draw: the official picture on the front, opaque grey metal on the reverse.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, blend_mix, depth_draw_always;
uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 face_region = vec4(0.0,0.0,1.0,1.0);
uniform vec4 outline_rect = vec4(0.0,0.0,1.0,1.0);
uniform int outline_shape = 0; // circle, diamond, rectangle, triangle up/down, octagon
uniform float outline_aspect = 1.0;
uniform float corner_radius = 0.1;

float triangle_distance(vec2 p,float aspect,float r) {
	// Apex-up triangle filling the visible box; corners rounded by r like the sign's own drawing.
	vec2 a=vec2(-aspect+r,1.0-r),b=vec2(aspect-r,1.0-r),c=vec2(0.0,-1.0+r);
	vec2 e0=b-a,e1=c-b,e2=a-c,v0=p-a,v1=p-b,v2=p-c;
	vec2 q0=v0-e0*clamp(dot(v0,e0)/dot(e0,e0),0.0,1.0);
	vec2 q1=v1-e1*clamp(dot(v1,e1)/dot(e1,e1),0.0,1.0);
	vec2 q2=v2-e2*clamp(dot(v2,e2)/dot(e2,e2),0.0,1.0);
	float s=sign(e0.x*e2.y-e0.y*e2.x);
	vec2 d=min(min(vec2(dot(q0,q0),s*(v0.x*e0.y-v0.y*e0.x)),vec2(dot(q1,q1),s*(v1.x*e1.y-v1.y*e1.x))),vec2(dot(q2,q2),s*(v2.x*e2.y-v2.y*e2.x)));
	return -sqrt(d.x)*sign(d.y)-r;
}
void fragment() {
	vec4 image=texture(picture,face_region.xy+UV*face_region.zw);
	vec2 p=(UV-outline_rect.xy)/outline_rect.zw*2.0-1.0;
	float d=0.0;
	if (outline_shape==1) d=length(p)-1.0;
	else if (outline_shape==2) {
		float r=corner_radius;
		vec2 q=abs(vec2(p.x+p.y,p.y-p.x))*.70710678-vec2((1.0+r*.41421356)*.70710678-r);
		d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-r;
	} else if (outline_shape==3) {
		vec2 q=abs(p*vec2(outline_aspect,1.0))-vec2(outline_aspect,1.0)+vec2(corner_radius);
		d=length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-corner_radius;
	} else if (outline_shape==4 || outline_shape==5) d=triangle_distance(p*vec2(outline_aspect,outline_shape==5?-1.0:1.0),outline_aspect,corner_radius);
	else if (outline_shape==6) d=max(max(abs(p.x),abs(p.y)),(abs(p.x)+abs(p.y))*.70710678)-1.0;
	float edge=max(fwidth(d),.0001);
	float coverage=outline_shape==0 ? smoothstep(.5-fwidth(image.a),.5+fwidth(image.a)+.0001,image.a) : 1.0-smoothstep(-edge*.5,edge*.5,d);
	if (coverage<=.001) discard;
	ALPHA=coverage;
	if (FRONT_FACING) {
		ALBEDO=vec3(0.0);
		// Transparent artefacts/bolt holes in a catalogue bitmap are not holes in the steel.
		EMISSION=mix(vec3(1.0),image.rgb,smoothstep(0.0,.1,image.a));
	} else {
		ALBEDO=vec3(0.43,0.46,0.49);
	}
	ROUGHNESS=0.85;
}
