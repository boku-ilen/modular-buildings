shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

//// ===============================
//// BASE LAYER
//// ===============================
uniform sampler2D tex_base_albedo;
uniform sampler2D tex_base_normal;
uniform sampler2D tex_base_mra; // R=Metal G=Rough B=AO

//// ===============================
//// DIRT LAYER
//// ===============================
uniform sampler2D tex_dirt_albedo;
uniform sampler2D tex_dirt_normal;
uniform sampler2D tex_dirt_mra; // R=Metal G=Rough B=AO

//// ===============================
//// DIRT MASK
//// ===============================
uniform sampler2D tex_dirtmask; // Grayscale

//// ===============================
//// ARTIST CONTROLS
//// ===============================
uniform float base_texel_density : hint_range(0.01, 10.0) = 1.0;
uniform float dirt_texel_density : hint_range(0.01, 20.0) = 4.0;
uniform float dirtmask_texel_density : hint_range(0.01, 20.0) = 2.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 1.0;

//// ===============================
//// DEBUG
//// ===============================
uniform int debug_mode = 0; 
//// 0=final, 1=axis RGB, 2=dirt mask

//// ===============================
//// VARYINGS
//// ===============================
varying vec3 v_axis_mask;
varying vec3 v_local_pos;
varying vec3 v_local_scale;

//// ===============================
//// VERTEX SHADER
//// ===============================
void vertex() {
	// Local-space vertex position (no world-space needed)
	v_local_pos = VERTEX;

	// Extract local scale from MODEL_MATRIX
	v_local_scale = vec3(
    	length(MODEL_MATRIX[0].xyz),
    	length(MODEL_MATRIX[1].xyz),
    	length(MODEL_MATRIX[2].xyz)
);
    
    // Dominant axis in object-local space
    vec3 an = abs(NORMAL);
    float max_axis = max(max(an.x, an.y), an.z);
    v_axis_mask = vec3(
        step(max_axis - an.x, 0.0),
        step(max_axis - an.y, 0.0),
        step(max_axis - an.z, 0.0)
    );
}

//// ===============================
//// FRAGMENT SHADER
//// ===============================
void fragment() {
    // -------------------------
    // TRIPLANAR UVS (adjusted for Object Scale)
    // -------------------------
    vec2 uv_x = v_local_pos.zy * v_local_scale.zy * sign(v_axis_mask.x);
    vec2 uv_y = v_local_pos.xz * v_local_scale.xz * sign(v_axis_mask.y);
    vec2 uv_z = v_local_pos.xy * v_local_scale.xy * sign(v_axis_mask.z);

    vec2 proj_uv = uv_x * v_axis_mask.x + uv_y * v_axis_mask.y + uv_z * v_axis_mask.z;

    // -------------------------
    // UV SETS
    // -------------------------
    vec2 uv_base = proj_uv * base_texel_density;
    vec2 uv_dirt = proj_uv * dirt_texel_density;
    vec2 uv_mask = proj_uv * dirtmask_texel_density;

    // -------------------------
    // BASE LAYER
    // -------------------------
    vec3 base_albedo = texture(tex_base_albedo, uv_base).rgb;
    vec3 base_normal = texture(tex_base_normal, uv_base).xyz * 2.0 - 1.0;
    vec3 base_rmao  = texture(tex_base_mra, uv_base).rgb;

    // -------------------------
    // DIRT LAYER
    // -------------------------
    vec3 dirt_albedo = texture(tex_dirt_albedo, uv_dirt).rgb;
    vec3 dirt_normal = texture(tex_dirt_normal, uv_dirt).xyz * 2.0 - 1.0;
    vec3 dirt_rmao  = texture(tex_dirt_mra, uv_dirt).rgb;

    // -------------------------
    // DIRT MASK
    // -------------------------
    float mask = texture(tex_dirtmask, uv_mask).r;
    float dirtmask_final = clamp(mask * dirt_amount, 0.0, 1.0);

    // -------------------------
    // NORMAL MAP FIX (branchless)
    // -------------------------
    vec3 basenorm_x = vec3(0.0, base_normal.y, base_normal.x);
    vec3 basenorm_y = vec3(base_normal.x, 0.0, base_normal.y);
    vec3 basenorm_z = vec3(base_normal.x, base_normal.y, 0.0);
    vec3 base_world_normal = basenorm_x * v_axis_mask.x + basenorm_y * v_axis_mask.y + basenorm_z * v_axis_mask.z;

    vec3 dirtnorm_x = vec3(0.0, dirt_normal.y, dirt_normal.x);
    vec3 dirtnorm_y = vec3(dirt_normal.x, 0.0, dirt_normal.y);
    vec3 dirtnorm_z = vec3(dirt_normal.x, dirt_normal.y, 0.0);
    vec3 dirt_world_normal = dirtnorm_x * v_axis_mask.x + dirtnorm_y * v_axis_mask.y + dirtnorm_z * v_axis_mask.z;

    vec3 final_normal = normalize(mix(base_world_normal, dirt_world_normal, dirtmask_final));

    // -------------------------
    // MATERIAL BLEND
    // -------------------------
    vec3 albedo     = mix(base_albedo, dirt_albedo, dirtmask_final);
    float metallic  = mix(base_rmao.r, dirt_rmao.r, dirtmask_final);
    float roughness = mix(base_rmao.g, dirt_rmao.g, dirtmask_final);
    float ao        = mix(base_rmao.b, dirt_rmao.b, dirtmask_final);

    // -------------------------
    // OUTPUT
    // -------------------------
    ALBEDO     = albedo;
    METALLIC   = metallic;
    ROUGHNESS  = roughness;
    AO         = ao;
    NORMAL_MAP = final_normal;

    // -------------------------
    // DEBUG MODES
    // -------------------------
    if (debug_mode == 1) {
        ALBEDO = vec3(v_axis_mask.x, v_axis_mask.y, v_axis_mask.z);
        METALLIC = 0.0;
        ROUGHNESS = 1.0;
    } else if (debug_mode == 2) {
        ALBEDO = vec3(dirtmask_final);
        METALLIC = 0.0;
        ROUGHNESS = 1.0;
    }
}
