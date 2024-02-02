uniform mat4 mvp;
attribute vec3 position;
attribute vec3 normal;

varying vec3 v_normal;

void main() {
	v_normal = normal;
	gl_Position = mvp * vec4(position, 1);
}