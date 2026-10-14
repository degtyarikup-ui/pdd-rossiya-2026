// One draw: the official picture on the front, opaque grey metal on the reverse.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled, blend_mix, depth_draw_always;
uniform sampler2D picture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 face_region = vec4(0.0,0.0,1.0,1.0);
uniform vec4 outline_rect = vec4(0.0,0.0,1.0,1.0);
uniform int outline_shape = 0; // circle, diamond, rectangle, triangle up/down, octagon
uniform float outline_aspect = 1.0;
uniform float corner_radius = 0.1;

float segment_distance(vec2 p,vec2 a,vec2 b) {
	vec2 v=p-a,e=b-a;
	return length(v-e*clamp(dot(v,e)/dot(e,e),0.0,1.0));
}
float triangle_distance(vec2 p) {
	// Small rounded corners, retained inside the original visible envelope.
	vec2 a=vec2(-.96,.96),b=vec2(.96,.96),c=vec2(0.0,-.96);
	float edge=min(segment_distance(p,a,b),min(segment_distance(p,b,c),segment_distance(p,c,a)));
	bool inside=p.y<.96 && p.y>2.0*p.x-.96 && p.y>-2.0*p.x-.96;
	return (inside?-edge:edge)-.04;
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
	} else if (outline_shape==4 || outline_shape==5) d=triangle_distance(p*vec2(1.0,outline_shape==5?-1.0:1.0));
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
