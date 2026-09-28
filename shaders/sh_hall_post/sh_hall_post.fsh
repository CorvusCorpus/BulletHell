// The hall's post-process (see `hall_post` in `scripts/bg_sanctum`), in
// three modes:
//
// 0. The bright pass: a quarter-size copy of the hall, keeping only what is
//    over `u_thresh`. Four bilinear taps cover the 4x4 texels one target
//    texel stands for.
// 1. One direction of a Gaussian blur (`u_dir` is a texel step).
// 2. The hall itself, graded: a vignette, and a lift of the deepest shadows
//    toward the air colour so black never crushes to flat.

varying vec2 v_vTexcoord;
varying vec4 v_vColour;

uniform float u_mode;
uniform vec2 u_texel;
uniform vec2 u_dir;
uniform float u_thresh;
uniform float u_vignette;
uniform vec3 u_lift;

void main() {
    if (u_mode < 0.5) {
        vec3 c = texture2D(gm_BaseTexture, v_vTexcoord + u_texel * vec2(-1.0, -1.0)).rgb
               + texture2D(gm_BaseTexture, v_vTexcoord + u_texel * vec2( 1.0, -1.0)).rgb
               + texture2D(gm_BaseTexture, v_vTexcoord + u_texel * vec2(-1.0,  1.0)).rgb
               + texture2D(gm_BaseTexture, v_vTexcoord + u_texel * vec2( 1.0,  1.0)).rgb;
        c *= 0.25;
        float l = max(c.r, max(c.g, c.b));
        // A soft knee: brightness over the threshold passes, scaled so the
        // colour is kept.
        float k = max(l - u_thresh, 0.0);
        k = k * k / (k + 0.12);
        gl_FragColor = vec4(c * (k / max(l, 0.0001)), 1.0);
        return;
    }
    if (u_mode < 1.5) {
        // Nine texels in five taps (linear sampling does the in-betweens).
        vec3 c = texture2D(gm_BaseTexture, v_vTexcoord).rgb * 0.2270270;
        vec2 o1 = u_dir * 1.3846154;
        vec2 o2 = u_dir * 3.2307692;
        c += texture2D(gm_BaseTexture, v_vTexcoord + o1).rgb * 0.3162162;
        c += texture2D(gm_BaseTexture, v_vTexcoord - o1).rgb * 0.3162162;
        c += texture2D(gm_BaseTexture, v_vTexcoord + o2).rgb * 0.0702703;
        c += texture2D(gm_BaseTexture, v_vTexcoord - o2).rgb * 0.0702703;
        gl_FragColor = vec4(c, 1.0);
        return;
    }
    vec3 c = texture2D(gm_BaseTexture, v_vTexcoord).rgb;
    vec2 q = (v_vTexcoord - 0.5) * vec2(1.0, 1.15);
    c *= clamp(1.0 - u_vignette * dot(q, q) * 2.2, 0.0, 1.0);
    c = c + u_lift * (1.0 - clamp(c * 6.0, 0.0, 1.0));
    gl_FragColor = vec4(c, 1.0);
}
