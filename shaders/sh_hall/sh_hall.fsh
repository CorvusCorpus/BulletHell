varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vFog;

uniform vec3 u_fogcol;
uniform float u_alpharef;

void main() {
    vec4 t = texture2D(gm_BaseTexture, v_vTexcoord);

    // The alpha test (which a custom shader must do itself), against the
    // texture's alpha rather than the faded result, so distance fading stays
    // a smooth fade instead of turning into a hard cut.
    if (t.a < u_alpharef) discard;

    vec4 c = v_vColour * t;
    // Fog toward the air colour for surfaces, toward black for lights (the
    // uniform is set per pass).
    c.rgb = mix(c.rgb, u_fogcol, v_vFog);
    gl_FragColor = c;
}
