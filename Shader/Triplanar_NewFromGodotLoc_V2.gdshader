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

varying vec3 v_triplanar_pos;
varying vec3 v_local_normal; // Used for determining dominant axis of Vertex -> which Projection Axis to use

// WARNING: Meshes must NOT use negative scale, this is not considered!


void vertex() {
	v_local_normal = NORMAL; // Pass local normal through to fragment (we'll pick dominant axis per-pixel)
	vec3 normal = NORMAL; // Maybe not required?

	TANGENT = vec3(0.0, 0.0, -1.0) * abs(normal.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(normal.z);
	TANGENT = normalize(TANGENT);

	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(normal.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(normal.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(normal.z);
	BINORMAL = normalize(BINORMAL);

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
	v_triplanar_pos = world_to_obj_axes * vertex_wp;
	v_triplanar_pos *= vec3(1.0, -1.0, 1.0);

}


vec4 triplanar_texture(sampler2D in_sampler, vec3 in_axis_mask, vec3 in_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(in_sampler, in_triplanar_pos.xy) * in_axis_mask.z;
	samp += texture(in_sampler, in_triplanar_pos.xz) * in_axis_mask.y;
	samp += texture(in_sampler, in_triplanar_pos.zy * vec2(-1.0, 1.0)) * in_axis_mask.x;
	return samp;
}

void fragment() {
    // -------------------------
    // DOMINANT AXIS (PER-PIXEL, HARD / ONE-HOT)
    // -------------------------
    vec3 n = normalize(v_local_normal);
    vec3 an = abs(n);
    // one-hot winner (avoids ties turning on multiple axes)
    float x_wins = step(an.y, an.x) * step(an.z, an.x);
    float y_wins = step(an.x, an.y) * step(an.z, an.y);
    float z_wins = 1.0 - max(x_wins, y_wins);
    vec3 axis_mask = vec3(x_wins, y_wins, z_wins);
    // sign of local normal (+1 / -1) per axis
    vec3 axis_sign = vec3(
        mix(-1.0, 1.0, step(0.0, n.x)),
        mix(-1.0, 1.0, step(0.0, n.y)),
        mix(-1.0, 1.0, step(0.0, n.z))
		);
	
    // Optional: flip U on negative-facing projections to reduce mirroring
    float fx = (axis_sign.x < 0.0) ? -1.0 : 1.0;
    float fy = (axis_sign.y < 0.0) ? -1.0 : 1.0;
    float fz = (axis_sign.z < 0.0) ? -1.0 : 1.0;
	
	///// NOT WORKING CORRECTLY YET!
	//vec2 uv_xaxis = vec2(v_triplanar_pos.z * fx, v_triplanar_pos.y);
	//vec2 uv_yaxis = vec2(v_triplanar_pos.x * fy, v_triplanar_pos.z);
	//vec2 uv_zaxis = vec2(v_triplanar_pos.x * fz, v_triplanar_pos.y);

	vec2 uv_xaxis = v_triplanar_pos.zy;
	vec2 uv_yaxis = v_triplanar_pos.zx;
	vec2 uv_zaxis = v_triplanar_pos.xy;
	
	
	
    
	vec2 proj_uv = uv_xaxis * axis_mask.x + uv_yaxis * axis_mask.y + uv_zaxis * axis_mask.z;
	
    // -------------------------
    // UV SETS
    // -------------------------
    vec2 uv_base = proj_uv * base_uv_density;
    vec2 uv_dirt = proj_uv * dirt_uv_density;
    vec2 uv_mask = proj_uv * dirtmask_uv_density;
	
	vec4 albedo_texsampled = triplanar_texture(base_albedo_tex, axis_mask, v_triplanar_pos);
	ALBEDO = albedo_texsampled.rgb * base_albedo_tint;
	ALBEDO = texture(base_albedo_tex, uv_base).rgb;

	//float metallic_texsampled = triplanar_texture(base_mra_tex, axis_mask, v_triplanar_pos).r;
	//METALLIC = metallic_texsampled;
	//SPECULAR = specular;
//
	//float roughness_texsampled = triplanar_texture(base_mra_tex, axis_mask, v_triplanar_pos).g;
	//ROUGHNESS = roughness_texsampled;

	// Normal Map: Enabled
	//NORMAL_MAP = triplanar_texture(tex_base_normal, axis_mask, uv_triplanar_pos).rgb;
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
    // -------------------------
    // DEBUG MODES
    // -------------------------
    if (debug_mode == 1) {
        ALBEDO = vec3(axis_mask.x, axis_mask.y, axis_mask.z);
        METALLIC = 0.0;
        ROUGHNESS = 1.0;
    }
	//else if (debug_mode == 2) {
        //ALBEDO = vec3(dirtmask_final);
        //METALLIC = 0.0;
        //ROUGHNESS = 1.0;
    //}
}
