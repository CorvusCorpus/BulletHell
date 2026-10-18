// The moon's shadow map: the depth along the moonlight, 0 at the shadow
// camera and 1 at the far side of its box (see `sh_wood_shadow.vsh`).

varying float v_depth;

void main() {
    gl_FragColor = vec4(v_depth, 0.0, 0.0, 1.0);
}
