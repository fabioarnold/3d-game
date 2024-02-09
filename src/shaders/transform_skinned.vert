uniform mat4 mvp;
uniform mat4 joints[32];
uniform float blend_skin;

attribute vec3 position;
attribute vec3 normal;
attribute vec2 texcoord;
attribute vec4 joint;
attribute vec4 weight;

varying vec3 v_normal;
varying vec2 v_texcoord;

void main() {
  mat4 skin = blend_skin * (weight.x * joints[int(joint.x)] +
                            weight.y * joints[int(joint.y)] +
                            weight.z * joints[int(joint.z)] +
                            weight.w * joints[int(joint.w)]);
  mat4 blended_skin = (1.0 - blend_skin) * mat4(1.0) + skin;

  v_normal = normal;
  v_texcoord = texcoord;
  gl_Position = mvp * blended_skin * vec4(position, 1.0);
}