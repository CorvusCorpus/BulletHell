// The wood's post-process (see `wood_post` in `scripts/bg_wood`), by
// `u_mode`:
//
// 0 the bright pass: a quarter-size copy keeping what is over `u_thresh`
//   (four bilinear taps cover the texels one target texel stands for);
// 1 one direction of a Gaussian blur (`u_dir` is a texel step);
// 2 the moon's rays: the sky's light (`u_rays`, from mode 4) smeared out
//   from the moon's place on screen (`u_sun`), fading along the way;
// 3 the wood itself, put together: its bloom and rays added, the highlights
//   rolled off rather than clipped, a vignette, and a dither so the dark
//   gradients of the fog don't band;
// 4 the rays' source: the scene where it is open sky (the depth buffer at
//   its far plane), and nothing where the wood stands in front of it.

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform float u_mode;
uniform vec2 u_texel;
uniform vec2 u_dir;
uniform float u_thresh;
uniform sampler2D u_bloom;
uniform sampler2D u_rays;
uniform sampler2D u_depth;
uniform vec2 u_sun;            // the moon on screen, 0..1
uniform vec4 u_rayp;           // length, decay, strength, how much of the sky
uniform vec3 u_raycol;
uniform float u_bloom_k;
uniform float u_vignette;
uniform vec3 u_lift;
uniform vec3 u_gain;
uniform vec4 u_flash;          // a wash over everything: colour, amount

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = v_vTexcoord;
    if (u_mode < 0.5) {
        vec3 c = texture2D(gm_BaseTexture, uv + u_texel * vec2(-1.0, -1.0)).rgb
               + texture2D(gm_BaseTexture, uv + u_texel * vec2( 1.0, -1.0)).rgb
               + texture2D(gm_BaseTexture, uv + u_texel * vec2(-1.0,  1.0)).rgb
               + texture2D(gm_BaseTexture, uv + u_texel * vec2( 1.0,  1.0)).rgb;
        c *= 0.25;
        float l = max(c.r, max(c.g, c.b));
        float k = max(l - u_thresh, 0.0);
        k = k * k / (k + 0.15);
        gl_FragColor = vec4(c * (k / max(l, 0.0001)), 1.0);
        return;
    }
    if (u_mode < 1.5) {
        vec3 c = texture2D(gm_BaseTexture, uv).rgb * 0.2270270;
        vec2 o1 = u_dir * 1.3846154;
        vec2 o2 = u_dir * 3.2307692;
        c += texture2D(gm_BaseTexture, uv + o1).rgb * 0.3162162;
        c += texture2D(gm_BaseTexture, uv - o1).rgb * 0.3162162;
        c += texture2D(gm_BaseTexture, uv + o2).rgb * 0.0702703;
        c += texture2D(gm_BaseTexture, uv - o2).rgb * 0.0702703;
        gl_FragColor = vec4(c, 1.0);
        return;
    }
    if (u_mode < 2.5) {
        // 24 taps toward the moon.
        vec2 st = (u_sun - uv) * u_rayp.x / 24.0;
        vec2 p = uv;
        float w = 1.0;
        vec3 acc = vec3(0.0);
        float norm = 0.0;
        for (int i = 0; i < 24; i++) {
            acc += texture2D(gm_BaseTexture, p).rgb * w;
            norm += w;
            w *= u_rayp.y;
            p += st;
        }
        gl_FragColor = vec4(acc / max(norm, 0.001), 1.0);
        return;
    }
    if (u_mode > 3.5) {
        // The rays' source, at a quarter size: four taps of the scene where
        // the depth says open sky.
        vec3 c = vec3(0.0);
        for (int i = 0; i < 4; i++) {
            vec2 o = vec2(mod(float(i), 2.0) * 2.0 - 1.0, floor(float(i) / 2.0) * 2.0 - 1.0);
            vec2 q = uv + u_texel * o;
            float z = texture2D(u_depth, q).r;
            float sky = step(0.99995, z);
            c += texture2D(gm_BaseTexture, q).rgb * sky;
        }
        c *= 0.25;
        float l = max(c.r, max(c.g, c.b));
        c *= smoothstep(u_rayp.w * 0.5, u_rayp.w * 1.5, l);
        gl_FragColor = vec4(c, 1.0);
        return;
    }
    vec3 c = texture2D(gm_BaseTexture, uv).rgb;
    c += texture2D(u_bloom, uv).rgb * u_bloom_k;
    c += texture2D(u_rays, uv).rgb * u_raycol * u_rayp.z;
    // A soft shoulder: the darks are left alone, bright things roll off.
    vec3 k = vec3(0.72);
    vec3 over = max(c - k, 0.0);
    c = min(c, k) + (1.0 - k) * (1.0 - exp(-over / (1.0 - k)));
    c = c * u_gain;
    c = mix(c, u_flash.rgb, u_flash.a);
    vec2 q = (uv - 0.5) * vec2(1.0, 1.12);
    c *= clamp(1.0 - u_vignette * dot(q, q) * 2.2, 0.0, 1.0);
    c = c + u_lift * (1.0 - clamp(c * 6.0, 0.0, 1.0));
    c += (hash(gl_FragCoord.xy) - 0.5) / 255.0;
    gl_FragColor = vec4(c, 1.0);
}
