// The hall's one shader. See `scripts/bg_sanctum`.
//
// **Distance has to take a surface's alpha away, not just its colour.** The
// stage fades its far end with hardware fog, which recolours a surface toward
// the air -- and that hides it only where what is *behind* it is the air too.
// At the end of this hall it is not: the rotunda is a lit backdrop hanging at
// the vanishing point, so a bay or a statue arriving at the fog's own end
// arrived as a fully fog-coloured silhouette cut out of a bright building. It
// was reported as things popping in, and fixing the fog colour made no
// difference at all, because the colour was never what was wrong.
//
// Alpha is the only thing that hides a surface whatever is behind it, and
// `vertex_submit` has no per-draw alpha -- the vertex buffer's own colour is
// what reaches the default shader, and the buffers are frozen. So the fade is
// computed here, from the one quantity a frozen buffer cannot carry: how far
// the vertex is from the camera *this frame*.
//
// The fog is done here too rather than being left to `gpu_set_fog`, so that
// one distance drives both and they cannot disagree about where the far end
// of the hall is.

attribute vec3 in_Position;
attribute vec4 in_Colour;
attribute vec2 in_TextureCoord;

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying float v_vFog;

uniform vec2 u_fog;     // where the air starts to thicken, and where it is solid
uniform vec2 u_fade;    // where a surface starts to go, and where it is gone

void main() {
    vec4 obj = vec4(in_Position.x, in_Position.y, in_Position.z, 1.0);
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION] * obj;

    // Eye distance rather than view-space z: a bay at the edge of a 74-degree
    // lens is a fifth further away than one dead ahead, and fading by z alone
    // puts the boundary on a plane the camera can see the corners of.
    float d = length((gm_Matrices[MATRIX_WORLD_VIEW] * obj).xyz);

    v_vFog = clamp((d - u_fog.x) / max(u_fog.y - u_fog.x, 1.0), 0.0, 1.0);
    float a = clamp((u_fade.y - d) / max(u_fade.y - u_fade.x, 1.0), 0.0, 1.0);

    v_vColour = vec4(in_Colour.rgb, in_Colour.a * a);
    v_vTexcoord = in_TextureCoord;
}
