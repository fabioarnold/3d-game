precision mediump float;
uniform sampler2D u_texture;
uniform vec4 u_color;
uniform vec3 u_sun;
uniform float u_effects;

varying vec3 v_normal;
varying vec2 v_texcoord;

void main() {
	// get texture color
	vec4 src = texture2D(u_texture, v_texcoord) * u_color;

	vec3 col = src.rgb;

	// lighten texture color based on normal
	float lighten = max(0.0, -dot(v_normal, u_sun));
	col = mix(col, vec3(1,1,1), lighten * 0.10 * u_effects);

	// shadow
	float darken = max(0.0, dot(v_normal, u_sun));
	col = mix(col, vec3(4.0/255.0, 27.0/255.0, 44.0/255.0), darken * 0.80 * u_effects);

	gl_FragColor = vec4(col, src.a);
}