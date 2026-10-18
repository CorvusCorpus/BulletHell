// The wood's sky (see `wood_draw_sky` in `scripts/bg_wood`), by `u_mode`:
//
// 0 the dome: the night's gradient and the moon's glow in the air
//   (`sky_col`, which `sh_wood` fogs toward, so the far wood melts into it);
// 1 stars, added, each twinkling at its own rate (its seed in `v_ex.x`);
// 2 the moon, with the eclipse's shadow crossing it (`u_ecl`);
// 3 a glow, added (the moon's corona, the ring leaving it);
// 4 clouds, lit from behind by the moon: dark bodies, bright edges.

varying vec3 v_dir;
varying vec4 v_col;
varying vec2 v_uv;
varying vec4 v_ex;

uniform float u_mode;
uniform float u_time;
uniform float u_bl;            // how far the sky has turned to blood
uniform float u_light;         // how much moonlight there is
uniform float u_amount;        // the pass's own strength (stars, glow)
uniform vec3 u_moon_vis;
uniform vec3 u_moon_col;       // the moon's face, already in its palette
uniform vec4 u_ecl;            // the shadow's centre (x, y in moon radii), radius, how dark
uniform vec3 u_umbra;          // the shadow's colour

uniform vec3 u_hor_a;
uniform vec3 u_hor_b;
uniform vec3 u_zen_a;
uniform vec3 u_zen_b;
uniform vec3 u_haze_a;
uniform vec3 u_haze_b;

// The same as `sky_col` in `sh_wood`; change both.
vec3 sky_col(vec3 d, float bl) {
    vec3 hor = mix(u_hor_a, u_hor_b, bl);
    vec3 zen = mix(u_zen_a, u_zen_b, bl);
    float up = clamp(d.y, 0.0, 1.0);
    vec3 c = mix(hor, zen, pow(smoothstep(-0.03, 0.55, up), 0.75));
    float m = max(dot(d, u_moon_vis), 0.0);
    vec3 haze = mix(u_haze_a, u_haze_b, bl);
    c += haze * (0.20 * pow(m, 4.0) + 0.42 * pow(m, 30.0)) * (0.35 + 0.65 * u_light);
    return c;
}

void main() {
    vec3 d = normalize(v_dir);
    if (u_mode < 0.5) {
        gl_FragColor = vec4(sky_col(d, u_bl), 1.0);
        return;
    }
    vec4 t = texture2D(gm_BaseTexture, v_uv);
    if (u_mode < 1.5) {
        float tw = 0.65 + 0.35 * sin(u_time * (0.03 + 0.05 * v_ex.x) + v_ex.x * 61.0);
        float a = t.a * v_col.a * tw * u_amount;
        gl_FragColor = vec4(v_col.rgb * a, a);
        return;
    }
    if (u_mode < 2.5) {
        // The moon's face (luminance in the texture), and the shadow: a
        // soft disc in the card's own space, deep copper inside.
        vec2 q = (v_uv - 0.5) * 2.0 / 0.94;
        vec2 e = q - u_ecl.xy;
        float r = length(e) / max(u_ecl.z, 0.001);
        float umb = 1.0 - smoothstep(0.70, 1.0, r);
        vec3 face = t.rgb * u_moon_col;
        vec3 c = mix(face, t.rgb * u_umbra, umb * u_ecl.w);
        gl_FragColor = vec4(c, t.a);
        return;
    }
    if (u_mode < 3.5) {
        float a = t.a * v_col.a * u_amount;
        gl_FragColor = vec4(v_col.rgb * a, a);
        return;
    }
    // Clouds: thin edges glow with the moon behind them, thick bodies stay
    // dark against the sky.
    float m = max(dot(d, u_moon_vis), 0.0);
    float near = pow(m, 10.0);
    float dens = t.a * v_col.a;
    float thin = 1.0 - smoothstep(0.15, 0.85, t.a);
    vec3 body = mix(u_hor_a, u_hor_b, u_bl) * 0.55;
    vec3 lit = mix(u_haze_a, u_haze_b, u_bl) * (0.18 + 2.6 * near) * u_light;
    vec3 c = body * t.r + lit * (0.20 + 0.80 * thin);
    gl_FragColor = vec4(c, dens * 0.55);
}
