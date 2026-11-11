#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform vec2 uPaneSize;
uniform float uRadius;
uniform float uDpr;
uniform float uRefraction;
uniform float uBevel;
uniform float uDispersion;
uniform float uRimBlur;
uniform vec2 uOptics;
uniform vec4 uCurves[12];
uniform vec3 uLight;
uniform vec4 uRim;
uniform float uHairline;
uniform sampler2D uTexture;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);
const float kPartReach = 10.0;
const float kPartHold = 7.0;
const float kLine = 0.67;
const float kLineCap = 0.298;
const float kCornerGap = 0.03;
const float kEndShade = 3.0;
const float kRimTail = 4.5;

float roundedBoxDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 roundedBoxNormal(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  vec2 n = q.x > 0.0 && q.y > 0.0
      ? normalize(q)
      : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
  return n * vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
}

float octantInset(vec2 point, float a, vec4 curve, vec2 center) {
  vec2 fromCenter = point - center;
  vec2 toJoint = curve.yz - center;
  if (toJoint.x * fromCenter.y < toJoint.y * fromCenter.x) {
    return curve.w - length(fromCenter);
  }
  float n = curve.x;
  vec2 s = max(point, 0.0) / a;
  float major = max(max(s.x, s.y), 1e-4);
  float norm = major * pow(1.0 + pow(min(s.x, s.y) / major, n), 1.0 / n);
  vec2 slope = pow(s / norm, vec2(n - 1.0));
  return a * (1.0 - norm) / max(length(slope), 1e-4);
}

float cornerInset(vec2 p, vec2 halfSize) {
  vec2 side = step(0.0, p);
  vec4 along = mix(
    mix(uCurves[0], uCurves[3], side.x),
    mix(uCurves[9], uCurves[6], side.x),
    side.y
  );
  vec4 across = mix(
    mix(uCurves[1], uCurves[4], side.x),
    mix(uCurves[10], uCurves[7], side.x),
    side.y
  );
  vec4 centers = mix(
    mix(uCurves[2], uCurves[5], side.x),
    mix(uCurves[11], uCurves[8], side.x),
    side.y
  );
  vec2 q = abs(p);
  if (along.x < 2.0) {
    return min(halfSize.x - q.x, halfSize.y - q.y);
  }
  float c = halfSize.x - halfSize.y;
  if (q.y + c >= q.x) {
    return octantInset(vec2(q.x, q.y + c), halfSize.x, along, centers.xy);
  }
  return octantInset(vec2(q.y, q.x - c), halfSize.y, across, centers.zw);
}

vec4 texel(vec2 pixel) {
  vec2 p = clamp(pixel, uOrigin + 0.5, uOrigin + uPaneSize * uDpr - 0.5);
#ifdef IMPELLER_TARGET_OPENGLES
  p.y = uSize.y - p.y;
#endif
  return texture(uTexture, clamp(p, vec2(0.5), uSize - 0.5) / uSize);
}

const float kGoldenAngle = 2.39996322973;
const float kFrostReach = 2.07846096908;

vec4 frostDisc(vec2 center, float reach, float falloff, int taps) {
  float decay = exp(-falloff / float(taps));
  float weight = sqrt(decay);
  vec2 turn = vec2(cos(kGoldenAngle), sin(kGoldenAngle));
  vec2 ray = vec2(1.0, 0.0);
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = 0; i < 64; i++) {
    if (i >= taps) break;
    float spread = sqrt((float(i) + 0.5) / float(taps));
    sum += texel(center + ray * reach * spread) * weight;
    total += weight;
    weight *= decay;
    ray = vec2(ray.x * turn.x - ray.y * turn.y, ray.x * turn.y + ray.y * turn.x);
  }
  return sum / total;
}

vec4 frosted(vec2 point, float frost) {
  vec2 center = uOrigin + point * uDpr;
  float sigma = frost * uDpr;
  sigma = sqrt(max(sigma * sigma - 0.25, 0.0));
  float reach = max(sigma - 0.5, 0.0) * kFrostReach;
  if (reach <= 0.0) {
    return texel(center);
  }
  float ratio = reach / sigma;
  float falloff = 0.5 * ratio * ratio;
  if (sigma <= 2.0) {
    return frostDisc(center, reach, falloff, 16);
  }
  if (sigma <= 3.5) {
    return frostDisc(center, reach, falloff, 32);
  }
  return frostDisc(center, reach, falloff, 64);
}

void main() {
  vec2 point = (FlutterFragCoord().xy - uOrigin) / uDpr;
  vec2 halfSize = uPaneSize * 0.5;
  vec2 centered = point - halfSize;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  float inset = max(-roundedBoxDistance(centered, halfSize, radius), 0.0);
  vec2 normal = roundedBoxNormal(centered, halfSize, radius);
  float edge = inset;
  bool lit = uHairline > 0.0 || uRim.w > 0.0 || uLight.x > 0.0;
  float traced = lit ? kLine + uLight.y : 0.0;
  if (traced > 0.0 && inset < traced + 1.0 / uDpr + kCornerGap * radius) {
    edge = max(cornerInset(centered, halfSize), 0.0);
  }
  float halfMinor = min(halfSize.x, halfSize.y);
  float bevel = max(min(uBevel, halfMinor * 0.5), 1e-3);
  float rise = 1.0 - clamp(inset / bevel, 0.0, 1.0);
  vec2 shift;
  if (uRefraction < 0.0) {
    shift = normal * -uRefraction * smoothstep(0.0, bevel, inset)
        * (1.0 - smoothstep(bevel, halfMinor, inset));
  } else {
    float depth = min(uRefraction, halfMinor) * (1.0 - sqrt(1.0 - rise * rise));
    shift = -normal * depth;
  }
  float frost = uRimBlur * rise * rise;
  vec4 base = frosted(point + shift, frost);
  if (uDispersion > 0.0 && inset < kPartReach) {
    vec2 part = normal.yx * 0.5 * uDispersion
        * (0.6 + 0.4 * abs(normal.y) * max(1.0 - inset / kPartHold, 0.0))
        * (1.0 - smoothstep(kPartHold, kPartReach, inset));
    vec4 red = frosted(point + shift + part, frost);
    vec4 blue = frosted(point + shift - part, frost);
    base = vec4(red.r, base.g, blue.b, max(base.a, max(red.a, blue.a)));
  }
  float alpha = base.a;
  vec3 color = base.rgb / max(alpha, 1e-4);
  color = mix(vec3(dot(color, kLuma)), color, uOptics.x) * uOptics.y;
  color *= 1.0 - uLight.z * abs(normal.x) * exp(-inset / kEndShade);
  vec3 glass = color * alpha;
  float within = max(edge - kLine, 0.0);
  float facing = smoothstep(0.65, 0.95, abs(normal.y));
  float band = clamp(1.0 - within / max(uLight.y, 1e-3), 0.0, 1.0);
  float tail = clamp(1.0 - max(inset - kLine, 0.0) / kRimTail, 0.0, 1.0);
  float shine = min(uLight.x * facing * mix(band, tail, uRim.x), 1.0);
  glass += (vec3(alpha) - (1.0 - uRim.z) * glass) * shine;
  float line = clamp((kLine - edge) * uDpr + 0.5, 0.0, 1.0);
  float across = abs(normal.x);
  float darken = mix(uHairline, uRim.w, across * across * across);
  if ((uHairline > 0.0 || uRim.w > 0.0) && line > 0.0) {
    vec4 under = frosted(point, 0.0);
    vec3 dark = max(under.rgb - kLineCap * under.a, 0.22 * under.rgb);
    glass = mix(glass, mix(under.rgb, dark, darken), line);
    alpha = mix(alpha, under.a, line);
  }
  fragColor = vec4(min(glass, vec3(alpha)), alpha);
}
