#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uResolution;
uniform float uTime;
uniform float uBrightness;

out vec4 fragColor;

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec2 uv = (fc * 2.0 - uResolution) / min(uResolution.x, uResolution.y);
  float t = uTime * 0.05;

  // Three colour palettes: cyan / violet / magenta (match original JS shader)
  vec3 pal0 = vec3(0.10, 0.80, 0.96);
  vec3 pal1 = vec3(0.36, 0.42, 0.99);
  vec3 pal2 = vec3(0.82, 0.30, 0.90);

  vec3 col = vec3(0.0);
  float lw = 0.002;
  float len = length(uv);
  float diag = mod(uv.x - uv.y, 0.2);

  for (int i = 0; i < 5; i++) {
    float fi = float(i);
    float w = lw * fi * fi;
    float d0 = max(abs(fract(t              + fi * 0.01) * 5.0 - len + diag), 1e-4);
    float d1 = max(abs(fract(t - 0.01       + fi * 0.01) * 5.0 - len + diag), 1e-4);
    float d2 = max(abs(fract(t - 0.02       + fi * 0.01) * 5.0 - len + diag), 1e-4);
    col += (w / d0) * pal0;
    col += (w / d1) * pal1;
    col += (w / d2) * pal2;
  }

  // Subtle dark-purple vignette
  col += vec3(0.05, 0.0, 0.05) * (1.0 - clamp(len, 0.0, 1.0));

  fragColor = vec4(col * uBrightness, 1.0);
}
