// A fragment program of the application's own (a Flutter "runtime effect", compiled by impellerc at build time):
// the four quarters of the rectangle it fills in four colours, so that a picture turned over or mirrored shows.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  if (p.y < 0.5) {
    fragColor = p.x < 0.5 ? vec4(1.0, 0.0, 0.0, 1.0) : vec4(0.0, 0.0, 1.0, 1.0);
  } else {
    fragColor = p.x < 0.5 ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(1.0, 1.0, 1.0, 1.0);
  }
}
