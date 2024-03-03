uniform mat4 u_viewprojection;

attribute vec3 a_position;
attribute vec2 a_texcoord;
attribute vec4 a_color;

varying vec2 v_texcoord;
varying vec4 v_color;

void main(void) {
  gl_Position = u_viewprojection * vec4(a_position, 1.0);
  v_texcoord = a_texcoord;
  v_color = a_color;
}
