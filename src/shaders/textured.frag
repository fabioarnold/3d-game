precision mediump float;
uniform sampler2D u_texture;
uniform vec4 u_color;

varying vec3 v_normal;
varying vec2 v_texcoord;

void main() {
	float l = 0.5 + 0.5 * dot(normalize(v_normal), normalize(vec3(0.5, -0.2, 1.0)));
	l = 0.5 + 0.5 * smoothstep(0.45, 0.55, l);
	vec4 color = texture2D(u_texture, v_texcoord) * u_color;
	gl_FragColor = vec4(l * color.rgb, color.a);
}