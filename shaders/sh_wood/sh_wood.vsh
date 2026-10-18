// The wood's shader (see `scripts/bg_wood`): the vertex stage.
//
// Everything in the wood stands on the ground, which is a function of world
// position (`ground`, the same sum as `wood_ground_y`). A mesh is built
// standing at y = 0; each vertex is raised by the ground under its anchor
// (a tree's foot, a tuft's root), or, with `conform`, under itself, so a root
// runs over a bump. The ground's own tiles are flat grids raised the same
// way, so the ground and what stands on it always agree.
//
// The kind of vertex (`ex.z / 4`): 0 a solid, 1 a ribbon (a twig, widened
// here across the line of sight to at least a pixel or so, with its true
// width kept as coverage), 2 a card, 3 a glow.

attribute vec3 in_Position;
attribute vec3 in_Normal;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;
attribute vec4 in_TextureCoord1;

varying vec3 v_pos;
varying vec3 v_nrm;
varying vec4 v_col;
varying vec2 v_uv;
varying vec4 v_shadow;
varying vec4 v_info;     // kind, ribbon side, ribbon coverage, ribbon width in px
varying float v_up;      // how high up its own mesh a vertex is (moss keeps low)

uniform vec3 u_cam;
uniform float u_time;
uniform vec4 u_wind;     // strength, gust, direction x, direction z
uniform float u_pix;     // world size of a pixel, per unit of distance
uniform mat4 u_shadow;   // world to the moon's shadow map
uniform float u_ground;  // 1: the ground's own tiles
uniform float u_raise;   // 1: stand on the ground (0 for what is placed whole, the charms)
uniform vec4 u_lane;     // the flight's lane (see `lane`)
uniform float u_follow;  // 1: laid out from the path's middle (the canopy, the hedge), so moved onto it

// The path's middle at depth `z`, and the ground's height at `p` (x, z).
// The same numbers as `wood_path_x` and `wood_ground_y`; change both.
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
    if (u_follow > 0.5) wp.x += path_x(wp.z);
    vec3 wn = (W * vec4(in_Normal, 0.0)).xyz;
    float wl = length(wn);
    wn = (wl > 0.0001) ? wn / wl : vec3(0.0, 1.0, 0.0);
    vec3 anc = (W * vec4(ex.x, 0.0, ex.y, 1.0)).xyz;
    // The scale the matrix applies (for a ribbon's radius).
    float scl = length(W[0].xyz);

    if (u_raise > 0.5) wp.y += mix(ground(anc.xz), ground(wp.xz), conform);

    // The wind: a slow lean with gusts running through the wood, more at
    // the ends of things (`ex.w`).
    if (ex.w > 0.0) {
        float ph = dot(wp.xz, vec2(0.0021, 0.0017));
        float gust = 0.6 + 0.4 * sin(u_time * 0.013 + ph * 2.3);
        float sway = sin(u_time * 0.045 + ph + wp.y * 0.004) * gust
                   + 0.35 * sin(u_time * 0.11 + ph * 3.1 + wp.y * 0.011);
        vec2 d = u_wind.zw * sway * u_wind.x * ex.w;
        wp.xz += d;
        wp.y -= abs(sway) * u_wind.x * ex.w * 0.15;
    }

    if (u_raise > 0.5 && u_ground < 0.5) wp = lane(wp);

    v_info = vec4(kind, 0.0, 1.0, 0.0);
    v_uv = in_TextureCoord;

    if (u_ground > 0.5) {
        // The ground: its texture laid by world position, and its normal
        // from the slope of the function it follows.
        float e = 6.0;
        float hx = ground(wp.xz + vec2(e, 0.0)) - ground(wp.xz - vec2(e, 0.0));
        float hz = ground(wp.xz + vec2(0.0, e)) - ground(wp.xz - vec2(0.0, e));
        wn = normalize(vec3(-hx, 2.0 * e, -hz));
        v_uv = wp.xz / 220.0;
    }

    if (kind > 0.5 && kind < 1.5) {
        // A ribbon: `wn` is the twig's direction. Its two edges go out
        // either side of it across the line of sight, by its radius or, if
        // that is under a pixel or so, by that, with the true width kept as
        // coverage for the fragment stage.
        vec3 to_cam = u_cam - wp;
        float dist = length(to_cam);
        vec3 side = cross(wn, to_cam / max(dist, 0.001));
        float sl = length(side);
        side = (sl > 0.0001) ? side / sl : vec3(1.0, 0.0, 0.0);
        float rad = in_TextureCoord.y * scl;
        float px = dist * u_pix;
        float w = max(rad, px * 0.75);
        wp += side * w * in_TextureCoord.x;
        v_info = vec4(kind, in_TextureCoord.x, clamp(rad / w, 0.0, 1.0),
                      w * 2.0 / max(px, 0.0001));
        v_uv = vec2(in_TextureCoord.x * 0.05 + 0.5, wp.y * 0.004);
    }

    v_up = in_Position.y * scl;
    v_pos = wp;
    v_nrm = wn;
    v_col = in_Colour;
    v_shadow = u_shadow * vec4(wp, 1.0);
    gl_Position = gm_Matrices[MATRIX_PROJECTION]
                * (gm_Matrices[MATRIX_VIEW] * vec4(wp, 1.0));
}
