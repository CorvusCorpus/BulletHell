// The wood's shader (see `scripts/bg_wood`): the fragment stage.
//
// A surface's colour is its texture times its vertex colour, lit per pixel:
//
// - the sky, as a hemisphere (the night above, the dark ground below), times
//   the occlusion baked into the vertex colour's alpha;
// - the moon, a directional light from ahead and above, shadowed by the
//   trees through the shadow map (`u_shadowmap`), with a rim where an edge
//   turns toward it, and through a leaf or a frond from behind;
// - the witch-lights and wisps, up to `LIGHTS` point lights;
// - the turn's wavefront: past it (ahead of `u_wave.x`) every colour is the
//   blood palette's, and along it a band of red light runs over everything.
//
// Then height fog toward the sky's own colour in that direction (so the far
// wood dissolves into the sky behind it), with the moon's glow in it.
//
// Bark and the ground are normal mapped without stored tangents: the frame
// is worked out from the screen-space derivatives of the position and the
// texture coordinates.

#extension GL_OES_standard_derivatives : enable

#define LIGHTS 12

varying vec3 v_pos;
varying vec3 v_nrm;
varying vec4 v_col;
varying vec2 v_uv;
varying vec4 v_shadow;
varying vec4 v_info;

uniform sampler2D u_nmap;      // the base texture's normal map
uniform sampler2D u_tex2;      // the ground: the path
uniform sampler2D u_nmap2;     // ...and its normal map
uniform sampler2D u_shadowmap;
uniform vec4 u_shadowp;        // texel size, bias, how dark, fade distance
uniform vec3 u_lorg;           // the shadow camera's position
uniform vec3 u_ldir;           // ...the way it looks
uniform float u_lrange;        // ...and how deep its box is

// The camera, and whether this is the ground. Named apart from the
// vertex stage's `u_eye` and `u_floor`: GameMaker sets a uniform of one
// name in one stage only, so a name declared in both is left at zero in
// the other.
uniform vec3 u_eye;
uniform float u_floor;
uniform float u_alpharef;
uniform vec4 u_mat;            // gloss, shininess, translucency, bump
uniform vec3 u_glowcol;        // a glow's light

uniform vec3 u_moon;           // toward the moonlight
uniform vec3 u_moon_vis;       // toward the moon's disc
uniform float u_light;         // how much moonlight there is (the eclipse)
uniform vec2 u_wave;           // the wavefront, ahead of the camera, and its depth
uniform vec4 u_flare;          // the front's own light: colour, and its width

// Night (a) and blood (b).
uniform vec3 u_sky_a;          // the sky's light from above
uniform vec3 u_sky_b;
uniform vec3 u_bounce_a;       // ...and from the ground
uniform vec3 u_bounce_b;
uniform vec3 u_moon_a;         // the moonlight
uniform vec3 u_moon_b;
uniform vec3 u_rim_a;          // moonlight on an edge
uniform vec3 u_rim_b;
uniform vec3 u_hor_a;          // the sky at the horizon (the fog)
uniform vec3 u_hor_b;
uniform vec3 u_zen_a;          // ...and overhead
uniform vec3 u_zen_b;
uniform vec3 u_haze_a;         // the moon's glow in the air
uniform vec3 u_haze_b;
uniform vec4 u_fogp;           // density, falloff with height, base height, most
uniform vec2 u_fogfar;         // where the wood starts to end, and is gone

uniform vec4 u_lpos[LIGHTS];   // xyz, reach (0: off)
uniform vec4 u_lcol[LIGHTS];   // colour (already scaled), unused

const float PI = 3.14159265;

// The sky's colour looking along `d`, in the palette `bl` (0 night, 1
// blood). The same as `sky_col` in `sh_wood_sky`; change both.
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

// The texture's normal map applied to `N` (the frame from derivatives).
vec3 bump(vec3 N, vec3 p, vec2 uv, vec3 m, float k) {
    vec3 dp1 = dFdx(p);
    vec3 dp2 = dFdy(p);
    vec2 du1 = dFdx(uv);
    vec2 du2 = dFdy(uv);
    vec3 r1 = cross(dp2, N);
    vec3 r2 = cross(N, dp1);
    vec3 T = r1 * du1.x + r2 * du2.x;
    vec3 B = r1 * du1.y + r2 * du2.y;
    float s = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
    vec3 t = m * 2.0 - 1.0;
    // The maps' green points up the picture, which is toward smaller v.
    t.y = -t.y;
    t.xy *= k;
    return normalize(T * s * t.x + B * s * t.y + N * t.z);
}

// How lit by the moon: the shadow map, nine taps for a soft edge, faded
// out with distance (beyond it the map doesn't reach).
float moon_shadow(vec4 sc, float ndl) {
    vec2 uv = vec2(sc.x * 0.5 + 0.5, 0.5 - sc.y * 0.5);
    if (uv.x <= 0.002 || uv.x >= 0.998 || uv.y <= 0.002 || uv.y >= 0.998) return 1.0;
    float d = dot(v_pos - u_lorg, u_ldir) / u_lrange
              - u_shadowp.y * (1.0 + 2.0 * (1.0 - clamp(ndl, 0.0, 1.0)));
    float t = u_shadowp.x * 1.25;
    float lit = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float s = texture2D(u_shadowmap, uv + vec2(float(i), float(j)) * t).r;
            lit += (d <= s) ? 1.0 : 0.0;
        }
    }
    lit /= 9.0;
    float far = length(v_pos - u_eye);
    lit = mix(lit, 1.0, smoothstep(u_shadowp.w * 0.8, u_shadowp.w, far));
    return mix(1.0, lit, u_shadowp.z);
}

void main() {
    float kind = v_info.x;
    vec3 p = v_pos;
    vec3 V = u_eye - p;
    float dist = length(V);
    V /= max(dist, 0.001);

    vec4 tex;
    vec3 N = normalize(v_nrm);
    float cover = 1.0;
    float path = 0.0;

    if (u_floor > 0.5) {
        // The forest floor, and the path worn through it: which is which by
        // distance from the path's middle, the edge broken by the litter's
        // own height so leaves lie over it.
        vec4 fl = texture2D(gm_BaseTexture, v_uv);
        vec4 pa = texture2D(u_tex2, v_uv * 1.3);
        float pz = p.z;
        float px = 150.0 * sin(pz * 0.000982) + 60.0 * sin(pz * 0.002327 + 1.3);
        float a = abs(p.x - px) + (fl.a - 0.5) * 120.0;
        path = 1.0 - smoothstep(120.0, 230.0, a);
        tex = mix(fl, pa, path);
        vec3 nm = mix(texture2D(u_nmap, v_uv).rgb, texture2D(u_nmap2, v_uv * 1.3).rgb, path);
        N = bump(N, p, v_uv, nm, u_mat.w);
        tex.a = 1.0;
    } else if (kind > 0.5 && kind < 1.5) {
        // A ribbon: shaded as the round twig it stands for, and its edges
        // faded over a pixel; its coverage is its true width.
        vec3 ax = N;
        vec3 vp = normalize(V - ax * dot(V, ax) + vec3(0.0, 0.0, 1e-5));
        vec3 sd = cross(ax, vp);
        float s = v_info.y;
        N = normalize(sd * s + vp * sqrt(max(1.0 - s * s, 0.0)));
        float edge = clamp((1.0 - abs(s)) * v_info.w * 0.5, 0.0, 1.0);
        cover = edge * v_info.z;
        tex = texture2D(gm_BaseTexture, v_uv);
        tex.a = 1.0;
    } else {
        tex = texture2D(gm_BaseTexture, v_uv);
        if (kind < 0.5) {
            if (dot(N, V) < 0.0) N = -N;
            N = bump(N, p, v_uv, texture2D(u_nmap, v_uv).rgb, u_mat.w);
            tex.a = 1.0;
        }
    }
    if (dot(N, V) < 0.0 && kind > 1.5) N = -N;

    float alpha = tex.a * cover;
    if (alpha < u_alpharef) discard;

    // The palette: night, or blood behind the wavefront.
    float ahead = p.z - u_eye.z;
    float bl = clamp((ahead - u_wave.x) / u_wave.y, 0.0, 1.0);
    vec3 alb = tex.rgb * v_col.rgb;
    float ao = v_col.a;

    if (kind > 2.5) {
        // A glow: its own light, as it is.
        vec3 c = alb * u_glowcol;
        gl_FragColor = vec4(c, alpha);
        return;
    }

    // --- the sky --------------------------------------------------------
    // The sky's light goes with the moon's at totality.
    vec3 amb = mix(mix(u_bounce_a, u_bounce_b, bl), mix(u_sky_a, u_sky_b, bl),
                   N.y * 0.5 + 0.5) * ao * mix(0.35, 1.0, u_light);

    // --- the moon -------------------------------------------------------
    vec3 L = u_moon;
    float ndl = dot(N, L);
    float sh = moon_shadow(v_shadow, ndl);
    vec3 mc = mix(u_moon_a, u_moon_b, bl) * u_light;
    vec3 dif = amb + mc * max(ndl, 0.0) * sh * (0.55 + 0.45 * ao);
    // The rim: an edge seen against the moon catches its light.
    float facing = max(dot(-V, u_moon_vis), 0.0);
    float rimf = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    vec3 rim = mix(u_rim_a, u_rim_b, bl) * u_light * rimf
               * (0.15 + 0.85 * facing * facing) * mix(0.35, 1.0, sh);
    // Through a leaf from behind.
    vec3 trans = mc * u_mat.z * max(-ndl, 0.0) * facing * sh;
    vec3 H = normalize(L + V);
    vec3 spc = mc * u_mat.x * pow(max(dot(N, H), 0.0), u_mat.y) * step(0.0, ndl) * sh;

    // --- the witch-lights ----------------------------------------------
    vec3 pl = vec3(0.0);
    for (int i = 0; i < LIGHTS; i++) {
        vec4 lp = u_lpos[i];
        if (lp.w <= 0.0) continue;
        vec3 d3 = lp.xyz - p;
        float r = length(d3);
        float x = r / lp.w;
        if (x >= 1.0) continue;
        float win = 1.0 - x * x;
        win *= win;
        float att = win / (1.0 + 14.0 * x * x);
        vec3 Ld = d3 / max(r, 0.001);
        float nl = dot(N, Ld);
        vec3 lc = u_lcol[i].rgb * att;
        pl += lc * clamp((nl + 0.3) / 1.3, 0.0, 1.0);
        pl += lc * u_mat.z * max(-nl, 0.0);
        spc += lc * u_mat.x * pow(max(dot(N, normalize(Ld + V)), 0.0), u_mat.y) * step(0.0, nl);
    }

    vec3 c = alb * (dif + pl + trans) + rim * alb * 1.6 + spc;

    // --- the front ------------------------------------------------------
    float fd = (ahead - u_wave.x) / max(u_flare.w, 1.0);
    c += u_flare.rgb * exp(-fd * fd) * (0.25 + alb * 3.0);

    // --- the air --------------------------------------------------------
    float h0 = u_eye.y - u_fogp.z;
    float h1 = p.y - u_fogp.z;
    float f = u_fogp.y;
    float dh = h1 - h0;
    float od = (abs(dh) > 0.5)
               ? (exp(-f * h0) - exp(-f * h1)) / (f * dh)
               : exp(-f * h0);
    float fog = 1.0 - exp(-u_fogp.x * dist * od);
    fog = min(fog, u_fogp.w);
    fog = max(fog, smoothstep(u_fogfar.x, u_fogfar.y, dist));
    vec3 fc = sky_col(-V, bl);
    c = mix(c, fc, fog);

    gl_FragColor = vec4(c, alpha);
}
