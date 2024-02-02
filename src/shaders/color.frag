precision mediump float;
uniform sampler2D texture;

varying vec2 v_texCoord;
varying vec3 v_normal;

void main() {
	vec4 color = texture2D(texture, v_texCoord);
	float l = 0.5 + 0.5 * dot(normalize(v_normal), normalize(vec3(0.5, -0.2, 1.0)));
	gl_FragColor = vec4(l * color.rgb, 1);
}