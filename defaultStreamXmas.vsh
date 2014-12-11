#version 330 core

//
//  defaultStreamXmas.vsh
//  YAOGL2
//
//  Created by Yousry Abdallah on 09.12.13.
//  Copyright 2014 yousry.de. All rights reserved.
//

layout (location = 0) in vec3 clientPosition;
layout (location = 1) in vec3 clientNormal;  
layout (location = 2) in vec2 clientTexture; 
layout (location = 3) in vec3 clientTangent; 
layout (location = 4) in vec3 clientColor;

struct MaterialInfo {
    float Shininess;
    vec3 Ka; // ambient reflectivity
    float Reflection;
    vec3 Kd; // diffuse reflectivity
    float Refraction;
    vec3 Ks; // specular reflectivity
    float Eta;
    int texNum;
};

#ifndef __AMD__
layout (std140) uniform clientUniforms {
    vec3 clientEye;
    layout(row_major) mat4 clientModel;
    layout(row_major) mat4 clientMVP;
    layout(row_major) mat4 clientShadowMVP;
    layout(row_major) mat4 clientMVIT;
    MaterialInfo clientMaterial;
};
#else
layout (std140) uniform clientUniforms {
    vec3 clientEye;
    mat4 clientModel;
    mat4 clientMVP;
    mat4 clientShadowMVP;
    mat4 clientMVIT;
    MaterialInfo clientMaterial;
};
#endif

uniform mat4 clientViewMatrix;


out WorldSpace {
    vec3 vsPosition;
    vec3 vsNormal;
    vec3 vsTangent;
    vec3 vsBitangent;
};

out TextureSpace {
    vec3 vsReflectRay;
    vec3 vsRefractRay;
    vec2 vsTexture;
    vec3 vsColor;
};

out vec4 vsShadowProjection;

void main()
{
    vsColor = clientColor;
    vsTexture = clientTexture;
    vsPosition =  (clientModel * vec4(clientPosition, 1.0)).xyz;

    vsNormal =  normalize((clientMVIT * vec4(clientNormal, 0.0)).xyz);
    vsTangent = normalize((clientMVIT * vec4(clientTangent, 0.0)).xyz);
    vsBitangent = cross(vsNormal, vsTangent);

    vsShadowProjection =  clientShadowMVP * vec4(clientPosition, 1.0);


    vec3 workEyeDir = -(clientEye - clientPosition);
    vsReflectRay = reflect(workEyeDir, vsNormal );
    
    vsReflectRay = (clientViewMatrix * vec4(vsReflectRay,0 )).xyz;

    vsRefractRay = refract(workEyeDir, vsNormal, clientMaterial.Eta);

    gl_Position = clientMVP * vec4(clientPosition, 1.0);
}