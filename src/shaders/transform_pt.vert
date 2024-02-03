uniform mat4 mvp;
attribute vec3 position;
attribute vec2 texcoord;

varying vec2 v_texcoord;

void main() {
	v_texcoord = texcoord;
	gl_Position = mvp * vec4(position, 1);
}