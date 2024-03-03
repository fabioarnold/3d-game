precision mediump float;
uniform sampler2D u_texture;
// uniform float u_near;
// uniform float u_far;

varying vec2 v_texcoord;
varying vec4 v_color;

void main(void) {
  // apply color value
  vec4 color = texture2D(u_texture, v_texcoord);
  if (color.a < 0.1) {
    discard;
  }
  gl_FragColor = color * v_color;

  // apply depth values
  // gl_FragDepth = LinearizeDepth(gl_FragCoord.z, u_near, u_far);
}
