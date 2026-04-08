shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

//// GENERAL PARAMETERS
group_uniforms general_parameters;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform int debug_mode = 0; // Debug-view different things if >0
uniform float triplanar_blend_sharpness : hint_range(1, 150.0, 0.001); // ONLY USED FOR BLENDED MODE!
group_uniforms;

//// BASE LAYER
group_uniforms layer_base;
uniform vec4 base_albedo_tint : source_color = vec4(1.0); // Multiplied on top of _albedo_tex
uniform sampler2D base_albedo_tex : hint_default_white;
uniform sampler2D base_normal_tex : hint_normal;
uniform sampler2D base_mrao_tex : hint_default_white;// R=Metal G=Rough B=AO
uniform float base_uv_density : hint_range(0.01, 10.0) = 1.0; // Density = UV Tiling
group_uniforms;

//// DIRT LAYER
group_uniforms layer_dirt;
uniform sampler2D dirt_albedo_tex : hint_default_white; // Depending on whether "Simple" or "Expensive" method, this is either mixed with Base Layer, or multiplied on top of it (both methods using Dirtmask_Tex)
uniform vec4 dirt_albedo_tint : source_color = vec4(1.0); // Multiplied on top of _albedo_tex
// "Expensive Method": Disabled for Performance reason, currently only uses Tex to multiply on top
uniform sampler2D dirt_normal_tex : hint_normal;
uniform sampler2D dirt_mrao_tex : hint_default_white; // R=Metal G=Rough B=AO
uniform float dirt_uv_density : hint_range(0.01, 20.0) = 4.0; // Density = UV Tiling
group_uniforms;

//// DIRTMASK = Mask for Blending between pure Base layer, and Base Layer * Dirt Layer
group_uniforms dirtmask;
uniform sampler2D dirtmask_tex : hint_default_black; // Grayscale
uniform float dirtmask_amount : hint_range(0.0, 1.0) = 1.0; // Additionally reduces effect of Dirt Layer
uniform float dirtmask_uv_density : hint_range(0.01, 20.0) = 2.0;
group_uniforms;

varying vec3 v_triplanar_pos;
varying vec3 v_local_normal; // Used for determining dominant axis of Vertex -> which Projection Axis to use
varying vec3 v_triplanar_blend_normalinfluence; // ONLY USED FOR BLENDED MODE!

// WARNING: Meshes must NOT use negative scale, this is not considered!

//////// FUNC DEFINITIONS

vec3 blend_normals_whiteout(vec3 in_base_normal, vec3 in_dirt_normal) {
	vec3 base_n = normalize(in_base_normal);
	vec3 dirt_n = normalize(in_dirt_normal);

	return normalize(vec3(
		base_n.xy + dirt_n.xy,
		base_n.z * dirt_n.z
	));
}

vec3 blend_normalmaps_whiteout_masked(
	vec3 in_base_normal_encoded,
	vec3 in_dirt_normal_encoded,
	float in_mask_texsampled,
	float in_mask_amount
) {
	float mask = clamp(in_mask_texsampled * in_mask_amount, 0.0, 1.0);

	// Decode
	vec3 base_n = in_base_normal_encoded * 2.0 - 1.0;
	vec3 dirt_n = in_dirt_normal_encoded * 2.0 - 1.0;

	// Scale dirt detail strength
	dirt_n = normalize(dirt_n);
	vec2 dirt_xy = dirt_n.xy * mask;
	float dirt_z = sqrt(max(1.0 - dot(dirt_xy, dirt_xy), 0.0));
	vec3 dirt_n_scaled = normalize(vec3(dirt_xy, dirt_z));

	// Whiteout overlay
	vec3 final_n = blend_normals_whiteout(base_n, dirt_n_scaled);

	// Encode
	return final_n * 0.5 + 0.5;
}

vec4 triplanar_texture_hard(sampler2D in_sampler, float in_uv_density, vec3 in_triplanar_pos) { // Requires also input for which Layer UV Set to use - which needs to be precomputed somewhere before?
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
	
	vec3 p = in_triplanar_pos * in_uv_density;
	
	// Flip U on negative-facing projections to remove mirroring
	float fx = (axis_sign.x < 0.0) ? 1.0 : -1.0;
	float fy = (axis_sign.y < 0.0) ? -1.0 : 1.0;
	float fz = (axis_sign.z < 0.0) ? -1.0 : 1.0;
	// Multiply using these potentially inverted f's
	vec2 uv_xaxis = vec2(p.z * fx, p.y);
	vec2 uv_yaxis = vec2(p.x * fy, p.z);
	vec2 uv_zaxis = vec2(p.x * fz, p.y);
	
	vec2 proj_uv = uv_xaxis * axis_mask.x
	             + uv_yaxis * axis_mask.y
	             + uv_zaxis * axis_mask.z;
	
	return texture(in_sampler, proj_uv);
}

vec4 triplanar_texture_blended(sampler2D in_sampler, float in_uv_density, vec3 in_triplanar_pos, vec3 in_triplanar_blend_normalinfluence) {
    vec3 n = normalize(v_local_normal);

    vec3 axis_sign = vec3(
        mix(-1.0, 1.0, step(0.0, n.x)),
        mix(-1.0, 1.0, step(0.0, n.y)),
        mix(-1.0, 1.0, step(0.0, n.z))
    );

    float fx = (axis_sign.x < 0.0) ? 1.0 : -1.0;
    float fy = (axis_sign.y < 0.0) ? -1.0 : 1.0;
    float fz = (axis_sign.z < 0.0) ? -1.0 : 1.0;

    vec3 p = in_triplanar_pos * in_uv_density;

    vec4 samp = vec4(0.0);
    samp += texture(in_sampler, vec2(p.x * fz, p.y)) * in_triplanar_blend_normalinfluence.z; // Z -> xy
    samp += texture(in_sampler, vec2(p.x * fy, p.z)) * in_triplanar_blend_normalinfluence.y; // Y -> xz
    samp += texture(in_sampler, vec2(p.z * fx, p.y)) * in_triplanar_blend_normalinfluence.x; // X -> zy

    return samp;
}

//// VERTEX + FRAGMENT PART

void vertex() {
	v_local_normal = NORMAL; // Pass local normal through to fragment (we'll pick dominant axis per-pixel)
	vec3 normal = NORMAL; // Maybe not required?

	// --- Unsure, maybe fixes some orientation issues, but minimal visual impact, could be disabled for Performance reason? MAYBE INCORRECT? Original Godot Triplanar Shader uses this.
	//vec3 tangent_manip = normalize(vec3(
										//abs(normal.y) + abs(normal.z),
										//0.0,
										//-abs(normal.x)
									//));
	//TANGENT = tangent_manip;
//
	//vec3 binormal_manip = normalize(vec3(
										//0.0,
										//abs(normal.x) + abs(normal.z),
										//-abs(normal.y)
									//));
	//BINORMAL = binormal_manip;

	// --- World position of the vertex
	vec3 vertex_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// --- Rotation-only basis from MODEL_MATRIX (strip scale)
	vec3 ax = normalize(MODEL_MATRIX[0].xyz);
	vec3 ay = normalize(MODEL_MATRIX[1].xyz);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	// --- World -> Object-axes (inverse rotation via transpose)
	mat3 world_to_obj_axes = transpose(mat3(ax, ay, az));

	// World anchored coordinates expressed in object axes
	// => seamless UVs across meshes with identical rotation
	v_triplanar_pos = world_to_obj_axes * vertex_wp;
	v_triplanar_pos *= vec3(1.0, -1.0, 1.0);
	
	// Required for Triplanar Blended Only!
	v_triplanar_blend_normalinfluence = pow(abs(normal), vec3(triplanar_blend_sharpness));
	v_triplanar_blend_normalinfluence /= dot(v_triplanar_blend_normalinfluence, vec3(1.0));
}

void fragment() {
	vec3 axis_mask; // Just declared so DebugMode 1 doesn't throw error
	
	/////// HARD METHOD
	
	////// BASE LAYER TEX SAMPLING
	//vec3 base_albedo_texsampled = triplanar_texture_hard(base_albedo_tex, base_uv_density, v_triplanar_pos).rgb * base_albedo_tint.rgb;
	//vec3 base_normal_texsampled = triplanar_texture_hard(base_normal_tex, base_uv_density, v_triplanar_pos).xyz;
	//vec3 base_mrao_texsampled = triplanar_texture_hard(base_mrao_tex, base_uv_density, v_triplanar_pos).rgb;
//
    ////// DIRT LAYER TEX SAMPLING
    //vec3 dirt_albedo_texsampled = triplanar_texture_hard(dirt_albedo_tex, dirt_uv_density, v_triplanar_pos).rgb * dirt_albedo_tint.rgb;
	////vec3 dirt_normal_texsampled = triplanar_texture_hard(dirt_normal_tex, dirt_uv_density, v_triplanar_pos).xyz * 2.0 - 1.0;
    ////vec3 dirt_rmao_texsampled  = triplanar_texture_hard(dirt_mrao_tex, dirt_uv_density, v_triplanar_pos).rgb;
//
	////// DIRTMASK TEX SAMPLING
	//float dirtmask_texsampled = triplanar_texture_hard(dirtmask_tex, dirtmask_uv_density, v_triplanar_pos).r;
	
	////// BLENDED METHOD
	
	//// BASE LAYER TEX SAMPLING
	vec3 base_albedo_texsampled = triplanar_texture_blended(base_albedo_tex, base_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb * base_albedo_tint.rgb;
	vec3 base_normal_texsampled = triplanar_texture_blended(base_normal_tex, base_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb;
	vec3 base_mrao_texsampled = triplanar_texture_blended(base_mrao_tex, base_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb;
//
    //// DIRT LAYER TEX SAMPLING
    vec3 dirt_albedo_texsampled = triplanar_texture_blended(dirt_albedo_tex, dirt_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb * dirt_albedo_tint.rgb;
	vec3 dirt_normal_texsampled = triplanar_texture_blended(dirt_normal_tex, dirt_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb;
    vec3 dirt_mrao_texsampled  = triplanar_texture_blended(dirt_mrao_tex, dirt_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).rgb;
//
	//// DIRTMASK TEX SAMPLING
	float dirtmask_texsampled = triplanar_texture_blended(dirtmask_tex, dirtmask_uv_density, v_triplanar_pos, v_triplanar_blend_normalinfluence).r;
	

	
	
	////-------------------------
	//CALCULATE "final_" channels for use in Output. DEBUG MODES can change those channels!
	////-------------------------
	vec3 final_albedo;
	vec3 final_normal;
	float final_metallic;
	float final_roughness;
	float final_ao;
	
	if (debug_mode == 0) {
		float dirtmask_factor = dirtmask_texsampled * dirtmask_amount;
		final_albedo     = mix(base_albedo_texsampled, dirt_albedo_texsampled, dirtmask_factor); // 2 Versions: Dirt replaces Base Albedo.
		//final_albedo     = mix(base_albedo_texsampled, dirt_albedo_texsampled * base_albedo_texsampled, dirtmask_factor); // 2 Versions: Dirt multiplies on top of Base
		
		//final_normal    = base_normal_texsampled; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_metallic  = base_mrao_texsampled.r; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_roughness = base_mrao_texsampled.g; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		//final_ao        = base_mrao_texsampled.b; // Cheap method: Dirt Layer is only (optionally tinted) Greyscale layer that's multiplied on top of Base Layer, RMAo come from Base
		
		final_normal    = blend_normalmaps_whiteout_masked(base_normal_texsampled, dirt_normal_texsampled, dirtmask_texsampled, dirtmask_amount); // Expensive method: Complex blending of Base_Normal and Dirt_Normal
		final_roughness = mix(base_mrao_texsampled.g, dirt_mrao_texsampled.g, dirtmask_factor); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		final_metallic  = mix(base_mrao_texsampled.r, dirt_mrao_texsampled.r, dirtmask_factor); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
		final_ao        = mix(base_mrao_texsampled.b, dirt_mrao_texsampled.b, dirtmask_factor); // Expensive method: if Dirt Layer also uses Albedo+MRAo instead of just a Texture multiplying on top of Base Layer!
	}
	else if (debug_mode == 1) {
		final_albedo = vec3(axis_mask.x, axis_mask.y, axis_mask.z);
		final_normal = vec3(0.5, 0.5, 1.0);
		final_metallic = 0.0;
		final_roughness = 1.0;
		final_ao = 1.0;
    }
	else if (debug_mode == 2) {
		final_albedo = vec3(dirtmask_texsampled);
		final_normal = vec3(0.5, 0.5, 1.0);
		final_metallic = 0.0;
		final_roughness = 1.0;
		final_ao = 1.0;
    }
	else {
	final_albedo = vec3(1.0, 0.0, 1.0);
	final_normal = vec3(0.5, 0.5, 1.0);
	final_metallic = 0.0;
	final_roughness = 1.0;
	final_ao = 1.0;
	}
	
	
	
	
    // -------------------------
    // TESTING OUTPUT - ONCE THIS IS IN SHADERINCLUDE, PUT THIS INTO ACTUAL SHADERS THEMSELVES and disable here!
    // -------------------------
	ALBEDO     = final_albedo;
	METALLIC   = final_metallic;
	ROUGHNESS  = final_roughness;
	AO         = final_ao;
	NORMAL_MAP = final_normal;
	SPECULAR = specular;
	NORMAL_MAP_DEPTH = normal_scale;
}