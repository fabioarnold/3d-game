precision mediump float;
uniform sampler2D texture;

varying vec2 v_texcoord;
varying vec3 v_normal;

void main() {
	float l = 0.5 + 0.5 * dot(normalize(v_normal), normalize(vec3(0.5, -0.2, 1.0)));
	vec4 color = texture2D(texture, v_texcoord);
	gl_FragColor = vec4(l * color.rgb, color.a);
}