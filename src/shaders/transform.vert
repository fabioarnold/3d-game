uniform mat4 mvp;
attribute vec3 position;
attribute vec2 texCoord;
attribute vec3 normal;

varying vec2 v_texCoord;
varying vec3 v_normal;

void main() {
	v_normal = normal;
	v_texCoord = texCoord;
	gl_Position = mvp * vec4(position, 1);
}