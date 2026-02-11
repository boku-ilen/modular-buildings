shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

//// BASE LAYER
uniform sampler2D base_albedo_tex;
uniform vec3 base_albedo_tint = vec3(1.0);
uniform sampler2D base_normal_tex: hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D base_mra_tex; // R=Metal G=Rough B=AO

//// DIRT LAYER
uniform sampler2D dirt_albedo_tex;
uniform vec3 dirt_albedo_tint;
uniform sampler2D dirt_normal_tex : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_mra_tex; // R=Metal G=Rough B=AO

//// DIRT MASK
uniform sampler2D dirtmask_tex; // Grayscale

//// ARTIST CONTROLS
uniform float base_uv_density : hint_range(0.01, 10.0) = 1.0;
uniform float dirt_uv_density : hint_range(0.01, 20.0) = 4.0;
uniform float dirtmask_uv_density : hint_range(0.01, 20.0) = 2.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.5;

uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;

//// DEBUG SETTINGS
uniform int debug_mode = 0; 
// 0=final, 1=axis RGB, 2=dirt mask

uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
varying vec3 uv_triplanar_pos;

uniform float uv1_blend_sharpness : hint_range(0.0, 150.0, 0.001);
varying vec3 uv1_power_normal;

// WARNING: Meshes must NOT use negative scale, this is not considered!


void vertex() {
	vec3 normal = NORMAL;

	TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
	TANGENT = normalize(TANGENT);

	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	BINORMAL = normalize(BINORMAL);

	// UV1 Triplanar: Enabled
	uv1_power_normal = pow(abs(NORMAL), vec3(uv1_blend_sharpness));
	
	// --- World position of the vertex
    vec3 vertex_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

    // --- Rotation-only basis from MODEL_MATRIX (strip scale)
    vec3 ax = normalize(MODEL_MATRIX[0].xyz);
    vec3 ay = normalize(MODEL_MATRIX[1].xyz);
    vec3 az = normalize(MODEL_MATRIX[2].xyz);

    // world -> object-axes (inverse rotation via transpose)
    mat3 world_to_obj_axes = transpose(mat3(ax, ay, az));

    // World anchored coordinates expressed in object axes
    // => seamless UVs across meshes with identical rotation
	uv_triplanar_pos = world_to_obj_axes * vertex_wp;
	
	uv1_power_normal /= dot(uv1_power_normal, vec3(1.0));
	uv_triplanar_pos *= vec3(1.0, -1.0, 1.0);
}

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}

void fragment() {
	vec4 albedo_texsampled = triplanar_texture(base_albedo_tex, uv1_power_normal, uv_triplanar_pos);
	ALBEDO = albedo_texsampled.rgb * base_albedo_tint;

	float metallic_texsampled = triplanar_texture(base_mra_tex, uv1_power_normal, uv_triplanar_pos).r;
	METALLIC = metallic_texsampled;
	SPECULAR = specular;

	float roughness_texsampled = triplanar_texture(base_mra_tex, uv1_power_normal, uv_triplanar_pos).g;
	ROUGHNESS = roughness_texsampled;

	// Normal Map: Enabled
	//NORMAL_MAP = triplanar_texture(tex_base_normal, uv1_power_normal, uv1_triplanar_pos).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	//
    //// NEEDS IMPLEMENTATION!-------------------------
    //// BASE LAYER
    //// -------------------------
    //vec3 base_albedo = texture(tex_base_albedo, uv_base).rgb;
    //vec3 base_normal = texture(tex_base_normal, uv_base).xyz * 2.0 - 1.0;
    //vec3 base_rmao  = texture(tex_base_mra, uv_base).rgb;
//
    //// -------------------------
    //// DIRT LAYER
    //// -------------------------
    //vec3 dirt_albedo = texture(tex_dirt_albedo, uv_dirt).rgb;
    //vec3 dirt_normal = texture(tex_dirt_normal, uv_dirt).xyz * 2.0 - 1.0;
    //vec3 dirt_rmao  = texture(tex_dirt_mra, uv_dirt).rgb;
//
    //// -------------------------
    //// DIRT MASK
    //// -------------------------
    //float mask = texture(tex_dirtmask, uv_mask).r;
    //float dirtmask_final = clamp(mask * dirt_amount, 0.0, 1.0);
//
    //// -------------------------
    //// YOUR ORIGINAL NORMAL HANDLING (unchanged, but uses axis_mask now) - BROKEN!
    //// -------------------------
    //vec3 basenorm_x = vec3(0.0, base_normal.y, base_normal.x);
    //vec3 basenorm_y = vec3(base_normal.x, 0.0, base_normal.y);
    //vec3 basenorm_z = vec3(base_normal.x, base_normal.y, 0.0);
    //vec3 base_world_normal = basenorm_x * axis_mask.x + basenorm_y * axis_mask.y + basenorm_z * axis_mask.z;
//
    //vec3 dirtnorm_x = vec3(0.0, dirt_normal.y, dirt_normal.x);
    //vec3 dirtnorm_y = vec3(dirt_normal.x, 0.0, dirt_normal.y);
    //vec3 dirtnorm_z = vec3(dirt_normal.x, dirt_normal.y, 0.0);
    //vec3 dirt_world_normal = dirtnorm_x * axis_mask.x + dirtnorm_y * axis_mask.y + dirtnorm_z * axis_mask.z;
//
    //vec3 final_normal = normalize(mix(base_world_normal, dirt_world_normal, dirtmask_final));
//
    //// -------------------------
    //// MATERIAL BLEND
    //// -------------------------
    //vec3 albedo     = mix(base_albedo, dirt_albedo, dirtmask_final);
    //float metallic  = mix(base_rmao.r, dirt_rmao.r, dirtmask_final);
    //float roughness = mix(base_rmao.g, dirt_rmao.g, dirtmask_final);
    //float ao        = mix(base_rmao.b, dirt_rmao.b, dirtmask_final);
//
    //// -------------------------
    //// OUTPUT
    //// -------------------------
    //ALBEDO     = albedo;
    //METALLIC   = metallic;
    //ROUGHNESS  = roughness;
    //AO         = ao;
    ////NORMAL_MAP = final_normal;
//
    //// -------------------------
    //// DEBUG MODES
    //// -------------------------
    //if (debug_mode == 1) {
        //ALBEDO = vec3(axis_mask.x, axis_mask.y, axis_mask.z);
        //METALLIC = 0.0;
        //ROUGHNESS = 1.0;
    //} else if (debug_mode == 2) {
        //ALBEDO = vec3(dirtmask_final);
        //METALLIC = 0.0;
        //ROUGHNESS = 1.0;
    //}	
}
