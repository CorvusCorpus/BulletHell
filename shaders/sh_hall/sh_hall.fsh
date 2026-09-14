varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vFog;

uniform vec3 u_fogcol;
uniform float u_alpharef;

void main() {
    vec4 t = texture2D(gm_BaseTexture, v_vTexcoord);

    // **The cut-out is tested against the texture, not against the result.**
    // `gpu_set_alphatestenable` is a fixed-function state the *default* shader
    // implements, so a custom one has to do its own -- and doing it on the
    // final alpha would mean a prop being faded out by distance stopped being
    // a fade and became a hard cut the moment it passed the reference. What
    // the test is for is the shape of a tabard, which is a property of the
    // texture and of nothing else.
    if (t.a < u_alpharef) discard;

    vec4 c = v_vColour * t;
    // Toward the air for a surface and toward black for a light, which is the
    // whole difference between the hall's two passes: distance washes a wall
    // out and takes a lamp away.
    c.rgb = mix(c.rgb, u_fogcol, v_vFog);
    gl_FragColor = c;
}
