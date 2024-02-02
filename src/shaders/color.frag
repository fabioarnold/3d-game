precision mediump float;
uniform vec4 color;

varying vec3 v_normal;

void main() {
	float l = 0.5 + 0.5 * dot(normalize(v_normal), vec3(0.0, 0.0, 1.0));
	gl_FragColor = vec4(l * color.rgb, 1);
}