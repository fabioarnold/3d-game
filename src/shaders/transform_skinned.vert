uniform mat4 u_mvp;
uniform mat4 u_joints[32];
uniform float u_blend_skin;

attribute vec3 a_position;
attribute vec3 a_normal;
attribute vec2 a_texcoord;
attribute vec4 a_joint;
attribute vec4 a_weight;

varying vec3 v_normal;
varying vec2 v_texcoord;

void main() {
  mat4 skin = u_blend_skin * (a_weight.x * u_joints[int(a_joint.x)] +
                              a_weight.y * u_joints[int(a_joint.y)] +
                              a_weight.z * u_joints[int(a_joint.z)] +
                              a_weight.w * u_joints[int(a_joint.w)]);
  mat4 blended_skin = (1.0 - u_blend_skin) * mat4(1.0) + skin;

  v_normal = a_normal;
  v_texcoord = a_texcoord;
  gl_Position = u_mvp * blended_skin * vec4(a_position, 1.0);
}