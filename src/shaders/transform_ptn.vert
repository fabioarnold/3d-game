uniform mat4 mvp;
attribute vec3 position;
attribute vec2 texcoord;
attribute vec3 normal;

varying vec2 v_texcoord;
varying vec3 v_normal;

void main() {
	v_normal = normal;
	v_texcoord = texcoord;
	gl_Position = mvp * vec4(position, 1);
}