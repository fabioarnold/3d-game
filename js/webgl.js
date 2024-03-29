let webgl2Supported = typeof WebGL2RenderingContext !== "undefined";
let webgl_fallback = false;
let gl;

let webglOptions = {
  alpha: true, //Boolean that indicates if the canvas contains an alpha buffer.
  antialias: true, //Boolean that indicates whether or not to perform anti-aliasing.
  depth: 32, //Boolean that indicates that the drawing buffer has a depth buffer of at least 16 bits.
  failIfMajorPerformanceCaveat: false, //Boolean that indicates if a context will be created if the system performance is low.
  powerPreference: "default", //A hint to the user agent indicating what configuration of GPU is suitable for the WebGL context. Possible values are:
  premultipliedAlpha: true, //Boolean that indicates that the page compositor will assume the drawing buffer contains colors with pre-multiplied alpha.
  preserveDrawingBuffer: true, //If the value is true the buffers will not be cleared and will preserve their values until cleared or overwritten by the author.
  stencil: true, //Boolean that indicates that the drawing buffer has a stencil buffer of at least 8 bits.
};

if (webgl2Supported) {
  gl = $canvasgl.getContext("webgl2", webglOptions);
  if (!gl) {
    throw new Error("The browser supports WebGL2, but initialization failed.");
  }
}
if (!gl) {
  webgl_fallback = true;
  gl = $canvasgl.getContext("webgl", webglOptions);

  if (!gl) {
    throw new Error("The browser does not support WebGL");
  }

  if (!gl.getExtension("OES_element_index_uint")) {
    throw new Error("The browser supports WebGL, but not the OES_element_index_uint extension");
  }
  let vaoExt = gl.getExtension("OES_vertex_array_object");
  if (!vaoExt) {
    throw new Error("The browser supports WebGL, but not the OES_vertex_array_object extension");
  }
  (gl.createVertexArray = vaoExt.createVertexArrayOES),
    (gl.deleteVertexArray = vaoExt.deleteVertexArrayOES),
    (gl.isVertexArray = vaoExt.isVertexArrayOES),
    (gl.bindVertexArray = vaoExt.bindVertexArrayOES),
    (gl.createVertexArray = vaoExt.createVertexArrayOES);
}
if (!gl) {
  throw new Error("The browser supports WebGL, but initialization failed.");
}

const glShaders = [];
const glPrograms = [];
const glVertexArrays = [];
const glBuffers = [];
const glTextures = [];
const glUniformLocations = [];

const glInitShader = (sourcePtr, sourceLen, type) => {
  const source = readCharStr(sourcePtr, sourceLen);
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw "Error compiling shader:" + gl.getShaderInfoLog(shader);
  }
  glShaders.push(shader);
  return glShaders.length - 1;
};
const glCreateProgram = () => {
  const program = gl.createProgram();
  glPrograms.push(program);
  return glPrograms.length - 1;
};
const glAttachShader = (programId, shaderId) => gl.attachShader(glPrograms[programId], glShaders[shaderId]);
const glLinkProgram = (programId) => {
  const program = glPrograms[programId];
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw "Error linking program:" + gl.getProgramInfoLog(program);
  }
};
const glLinkShaderProgram = (vertexShaderId, fragmentShaderId) => {
  const program = gl.createProgram();
  gl.attachShader(program, glShaders[vertexShaderId]);
  gl.attachShader(program, glShaders[fragmentShaderId]);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw "Error linking program:" + gl.getProgramInfoLog(program);
  }
  glPrograms.push(program);
  return glPrograms.length - 1;
};

function createGLTexture(ctx, image, texture) {
  ctx.bindTexture(ctx.TEXTURE_2D, texture);
  ctx.texImage2D(ctx.TEXTURE_2D, 0, ctx.RGBA, ctx.RGBA, ctx.UNSIGNED_BYTE, image);
  ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_MAG_FILTER, ctx.NEAREST);
  ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_MIN_FILTER, ctx.NEAREST_MIPMAP_NEAREST);
  ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_WRAP_S, ctx.REPEAT);
  ctx.texParameteri(ctx.TEXTURE_2D, ctx.TEXTURE_WRAP_T, ctx.REPEAT);
  ctx.generateMipmap(ctx.TEXTURE_2D);
  ctx.bindTexture(ctx.TEXTURE_2D, null);
}

function loadImageTexture(gl, url) {
  const texture = gl.createTexture();
  texture.image = new Image();
  texture.image.crossOrigin = "";
  texture.image.onload = function () {
    createGLTexture(gl, texture.image, texture);
  };
  texture.image.src = url;
  return texture;
}

function jsLoadTextureIMG(dataPtr, dataLen, mimePtr, mimeLen, widthPtr, heightPtr) {
  const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
  const textureId = glCreateTexture();
  const img = new Image();
  images.push(img); // track loading progress
  const mime = readCharStr(mimePtr, mimeLen);
  img.src = URL.createObjectURL(new Blob([data], { type: mime }));
  img.onload = () => {
    if (widthPtr) new Uint16Array(memory.buffer, widthPtr, 1)[0] = img.width;
    if (heightPtr) new Uint16Array(memory.buffer, heightPtr, 1)[0] = img.height;
    createGLTexture(gl, img, glTextures[textureId]);
  };
  return textureId;
}

const glViewport = (x, y, width, height) => gl.viewport(x, y, width, height);
const glClearColor = (r, g, b, a) => gl.clearColor(r, g, b, a);
const glEnable = (x) => gl.enable(x);
const glDisable = (x) => gl.disable(x);
const glCullFace = (x) => gl.cullFace(x);
const glDepthMask = (x) => gl.depthMask(x);
const glDepthFunc = (x) => gl.depthFunc(x);
const glBlendFunc = (x, y) => gl.blendFunc(x, y);
const glClear = (x) => gl.clear(x);
const jsBindAttribLocation = (programId, index, namePtr, nameLen) =>
  gl.bindAttribLocation(glPrograms[programId], index, readCharStr(namePtr, nameLen));
const glGetAttribLocation = (programId, namePtr, nameLen) =>
  gl.getAttribLocation(glPrograms[programId], readCharStr(namePtr, nameLen));
const glGetUniformLocation = (programId, namePtr, nameLen) => {
  glUniformLocations.push(gl.getUniformLocation(glPrograms[programId], readCharStr(namePtr, nameLen)));
  return glUniformLocations.length - 1;
};
const jsGetUniformLocation = (programId, namePtr, nameLen) => {
  glUniformLocations.push(gl.getUniformLocation(glPrograms[programId], readCharStr(namePtr, nameLen)));
  return glUniformLocations.length - 1;
};
const glUniform3f = (locationId, x, y, z) => gl.uniform3fv(glUniformLocations[locationId], [x, y, z]);
const glUniform4f = (locationId, x, y, z, w) => gl.uniform4fv(glUniformLocations[locationId], [x, y, z, w]);
const glUniformMatrix4fv = (locationId, dataLen, transpose, dataPtr) => {
  const floats = new Float32Array(memory.buffer, dataPtr, dataLen * 16);
  gl.uniformMatrix4fv(glUniformLocations[locationId], transpose, floats);
};
const glUniform1i = (locationId, x) => gl.uniform1i(glUniformLocations[locationId], x);
const glUniform1f = (locationId, x) => gl.uniform1f(glUniformLocations[locationId], x);
const glCreateBuffer = () => {
  glBuffers.push(gl.createBuffer());
  return glBuffers.length - 1;
};
const glGenBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateBuffer();
    buffers[n] = b;
  }
};
const glDetachShader = (program, shader) => {
  gl.detachShader(glPrograms[program], glShaders[shader]);
};
const glDeleteProgram = (id) => {
  gl.deleteProgram(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffer = (id) => {
  gl.deleteBuffer(glPrograms[id]);
  glPrograms[id] = undefined;
};
const glDeleteBuffers = (num, dataPtr) => {
  const buffers = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.deleteBuffer(buffers[n]);
    glBuffers[buffers[n]] = undefined;
  }
};
const glDeleteShader = (id) => {
  gl.deleteShader(glShaders[id]);
  glShaders[id] = undefined;
};
const glBindBuffer = (type, bufferId) => gl.bindBuffer(type, glBuffers[bufferId]);
const glBufferData = (type, count, dataPtr, drawType) => {
  const data = new Uint8Array(memory.buffer, dataPtr, count);
  gl.bufferData(type, data, drawType);
};
const glUseProgram = (programId) => gl.useProgram(glPrograms[programId]);
const glEnableVertexAttribArray = (x) => gl.enableVertexAttribArray(x);
const glDisableVertexAttribArray = (x) => gl.disableVertexAttribArray(x);
const glVertexAttribPointer = (index, size, type, normalized, stride, offset) => {
  gl.vertexAttribPointer(index, size, type, normalized, stride, offset);
};
const glDrawArrays = (mode, first, count) => gl.drawArrays(mode, first, count);
const glDrawElements = (mode, count, type, offset) => gl.drawElements(mode, count, type, offset);
const glCreateTexture = () => {
  glTextures.push(gl.createTexture());
  return glTextures.length - 1;
};
const glGenTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateTexture();
    textures[n] = b;
  }
};
const glDeleteTextures = (num, dataPtr) => {
  const textures = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.glCreateTexture(buffers[n]);
    glTextures[textures[n]] = undefined;
  }
};
const glDeleteTexture = (id) => {
  gl.deleteTexture(glShaders[id]);
  glTextures[id] = undefined;
};
const glBindTexture = (target, textureId) => gl.bindTexture(target, glTextures[textureId]);
const glTexImage2D = (target, level, internalFormat, width, height, border, format, type, dataPtr, dataLen) => {
  const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
  gl.texImage2D(target, level, internalFormat, width, height, border, format, type, data);
};
const glTexParameteri = (target, pname, param) => gl.texParameteri(target, pname, param);
const glActiveTexture = (target) => gl.activeTexture(target);
const glCreateVertexArray = () => {
  glVertexArrays.push(gl.createVertexArray());
  return glVertexArrays.length - 1;
};
const glGenVertexArrays = (num, dataPtr) => {
  const vaos = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    const b = glCreateVertexArray();
    vaos[n] = b;
  }
};
const glDeleteVertexArrays = (num, dataPtr) => {
  const vaos = new Uint32Array(memory.buffer, dataPtr, num);
  for (let n = 0; n < num; n++) {
    gl.glCreateTexture(vaos[n]);
    glVertexArrays[vaos[n]] = undefined;
  }
};
const glBindVertexArray = (id) => gl.bindVertexArray(glVertexArrays[id]);
const glPixelStorei = (type, alignment) => gl.pixelStorei(type, alignment);
const glGetError = () => gl.getError();

var webgl = {
  glInitShader,
  glLinkShaderProgram,
  glCreateProgram,
  glDeleteProgram,
  glAttachShader,
  glDetachShader,
  glDeleteShader,
  glLinkProgram,
  glViewport,
  glClearColor,
  glEnable,
  glDisable,
  glCullFace,
  glDepthMask,
  glDepthFunc,
  glBlendFunc,
  glClear,
  jsBindAttribLocation,
  glGetAttribLocation,
  jsGetUniformLocation,
  glUniform3f,
  glUniform4f,
  glUniformMatrix4fv,
  glUniform1i,
  glUniform1f,
  glCreateBuffer,
  glGenBuffers,
  glDeleteBuffer,
  glDeleteBuffers,
  glBindBuffer,
  glBufferData,
  glUseProgram,
  glEnableVertexAttribArray,
  glDisableVertexAttribArray,
  glVertexAttribPointer,
  glDrawArrays,
  glDrawElements,
  glCreateTexture,
  glGenTextures,
  glDeleteTextures,
  glDeleteTexture,
  glBindTexture,
  glTexImage2D,
  jsLoadTextureIMG,
  glTexParameteri,
  glActiveTexture,
  glCreateVertexArray,
  glGenVertexArrays,
  glDeleteVertexArrays,
  glBindVertexArray,
  glPixelStorei,
  glGetError,
};
