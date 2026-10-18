// The moon's shadow map (see `wood_draw_shadow` in `scripts/bg_wood`): the
// wood's solids from the moon's side, each pixel keeping its depth along the
// moonlight. The same ground and wind as `sh_wood` (change both), so a
// shadow stays under what casts it. Ribbons, cards and glows cast nothing
// (they are moved out of view): twigs that fine would only be noise in the
// map. Solids, bark or stone, cast.

attribute vec3 in_Position;
attribute vec3 in_Normal;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
attribute vec4 in_TextureCoord1;

varying float v_depth;

uniform float u_time;
uniform vec4 u_wind;
uniform vec3 u_lorg;     // the shadow camera's position
uniform vec3 u_ldir;     // ...the way it looks
uniform float u_lrange;  // ...and how deep its box is
uniform vec4 u_lane;     // the flight's lane (as `sh_wood`'s)

float path_x(float z) {
    return 150.0 * sin(z * 0.000982) + 60.0 * sin(z * 0.002327 + 1.3);
}

float ground(vec2 p) {
    float dx = p.x - path_x(p.y);
    float a = abs(dx);
    float trough = -14.0 * (1.0 - smoothstep(140.0, 300.0, a));
    float bank = 60.0 * smoothstep(220.0, 1100.0, a)
                 * (0.65 + 0.35 * sin(p.y * 0.0011 + sign(dx) * 1.7));
    float hum = 30.0 * sin(p.x * 0.0031 + p.y * 0.0017)
                     * sin(p.y * 0.0023 - p.x * 0.0013 + 1.1)
              + 16.0 * sin(p.x * 0.0071 - p.y * 0.0049 + 2.3)
                     * sin(p.y * 0.0063 + p.x * 0.0029);
    hum *= smoothstep(160.0, 500.0, a);
    return trough + bank + hum;
}

// The flight's lane: whatever reaches into it at the camera's height is
// lifted over it, so a limb that crosses the path arches above the camera
// rather than through it. `u_lane` is its half-width, the height things are
// lifted to, and the lowest height that is lifted.
vec3 lane(vec3 wp) {
    float dx = abs(wp.x - path_x(wp.z));
    float w = 1.0 - smoothstep(u_lane.x * 0.55, u_lane.x, dx);
    float inside = smoothstep(u_lane.z, u_lane.z + 50.0, wp.y);
    wp.y = mix(wp.y, max(wp.y, u_lane.y), w * inside);
    return wp;
}

void main() {
    vec4 ex = in_TextureCoord1;
    float kind = floor(ex.z * 0.25 + 0.001);
    float conform = ex.z - kind * 4.0;
    mat4 W = gm_Matrices[MATRIX_WORLD];
    vec3 wp = (W * vec4(in_Position, 1.0)).xyz;
    vec3 anc = (W * vec4(ex.x, 0.0, ex.y, 1.0)).xyz;
    wp.y += mix(ground(anc.xz), ground(wp.xz), conform);
    if (ex.w > 0.0) {
        float ph = dot(wp.xz, vec2(0.0021, 0.0017));
        float gust = 0.6 + 0.4 * sin(u_time * 0.013 + ph * 2.3);
        float sway = sin(u_time * 0.045 + ph + wp.y * 0.004) * gust
                   + 0.35 * sin(u_time * 0.11 + ph * 3.1 + wp.y * 0.011);
        wp.xz += u_wind.zw * sway * u_wind.x * ex.w;
        wp.y -= abs(sway) * u_wind.x * ex.w * 0.15;
    }
    wp = lane(wp);
    v_depth = dot(wp - u_lorg, u_ldir) / u_lrange;
    vec4 cp = gm_Matrices[MATRIX_PROJECTION] * (gm_Matrices[MATRIX_VIEW] * vec4(wp, 1.0));
    if (kind > 0.5 && kind < 3.5) cp = vec4(0.0, 0.0, -10.0, 1.0);
    gl_Position = cp;
}
