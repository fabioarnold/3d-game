uniform mat4 u_mvp;

attribute vec3 a_position;
attribute vec3 a_normal;
attribute vec2 a_texcoord;

varying vec3 v_normal;
varying vec2 v_texcoord;

void main() {
	v_normal = a_normal;
	v_texcoord = a_texcoord;
	gl_Position = u_mvp * vec4(a_position, 1);
}