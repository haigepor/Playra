#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uCaptureSize;
uniform vec2 uCaptureOffset;
uniform float uSelection;
uniform float uSlotWidth;
uniform float uPress;
uniform float uMotion;
uniform vec4 uTint;
uniform vec3 uAccent;
uniform sampler2D uBackdrop;
out vec4 fragColor;

float roundedDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 roundedNormal(vec2 p, vec2 halfSize, float radius) {
  vec2 corner = max(abs(p) - halfSize + radius, 0.0);
  if (dot(corner, corner) > 0.0001) return normalize(corner) * sign(p);
  vec2 remaining = halfSize - abs(p);
  return remaining.x < remaining.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}

vec3 backdrop(vec2 point) {
  vec2 uv = clamp((point + uCaptureOffset) / uCaptureSize, 0.0, 1.0);
  return texture(uBackdrop, uv).rgb;
}

void main() {
  vec2 point = FlutterFragCoord().xy;
  vec2 halfSize = uSize * 0.5;
  float radius = halfSize.y;
  float distance = roundedDistance(point - halfSize, halfSize, radius);
  float alpha = 1.0 - smoothstep(-0.75, 0.75, distance);
  vec2 normal = roundedNormal(point - halfSize, halfSize, radius);
  float edge = pow(1.0 - clamp(-distance / 9.0, 0.0, 1.0), 2.4);

  vec2 lensHalf = vec2(
    (uSlotWidth - 10.0) * (1.0 + uPress * 0.045 + abs(uMotion) * 0.06),
    (uSize.y - 12.0) * (1.0 - uPress * 0.075)
  ) * 0.5;
  vec2 lensPoint = point - vec2(uSelection, halfSize.y);
  float lensDistance = roundedDistance(lensPoint, lensHalf, lensHalf.y);
  float lensMask = 1.0 - smoothstep(-0.7, 0.7, lensDistance);
  vec2 lensNormal = roundedNormal(lensPoint, lensHalf, lensHalf.y);
  float lensEdge = pow(1.0 - clamp(-lensDistance / 7.0, 0.0, 1.0), 2.0) * lensMask;

  vec2 shift = normal * edge * 4.0 + lensNormal * lensEdge * (1.8 + uPress * 1.2);
  vec2 refracted = point - shift;
  vec3 color = backdrop(refracted);
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, 0.70);
  // Keep the label area quiet even when bright covers or text pass behind it.
  float tint = uTint.a + smoothstep(0.40, 0.90, point.y / uSize.y) * 0.10;
  color = mix(color, uTint.rgb, min(tint, 0.90));
  color += (uAccent * 0.035 + vec3(0.025)) * lensMask;

  vec2 light = normalize(vec2(-0.38, -0.92));
  float rim = 1.0 - smoothstep(0.25, 1.35, abs(distance + 0.65));
  float reflection = pow(max(dot(normal, light), 0.0), 8.0);
  color += vec3(0.78, 0.86, 1.0) * (rim * (0.12 + reflection * 0.30) + edge * reflection * 0.045);
  color *= 1.0 - edge * pow(max(dot(normal, -light), 0.0), 3.0) * 0.17;
  float lensRim = (1.0 - smoothstep(0.2, 1.25, abs(lensDistance + 0.55))) * lensMask;
  color += vec3(0.8, 0.87, 1.0) * lensRim * (0.08 + 0.20 * pow(max(dot(lensNormal, light), 0.0), 6.0));
  fragColor = vec4(clamp(color, 0.0, 1.0) * alpha, alpha);
}
