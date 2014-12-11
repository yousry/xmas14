#version 330 core

//
//  defaultStreamXmas.fsh
//  YAOGL2
//
//  Created by Yousry Abdallah on 09.12.13.
//  Copyright 2014 yousry.de. All rights reserved.
//


#define LAMBERT_MAX 0.707107f

#define M_PI 3.141592654
#define M_PIPI 6.283185307
#define M_INV_PI 0.318309886
#define M_INV_LOG2 1.442695040

#define EPSILON 0.0001


in WorldSpace {
    vec3 vsPosition;
    vec3 vsNormal;
    vec3 vsTangent;
    vec3 vsBitangent;
};

in TextureSpace {
    vec3 vsReflectRay;
    vec3 vsRefractRay;
    vec2 vsTexture;
    vec3 vsColor;
};

in vec4 vsShadowProjection;



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


struct LightInfo {
    vec4 Position;
    vec3 Intensity;
};

struct SpotLightInfo {
    vec4 position;
    vec3 intensity;
    vec3 direction;
    float exponent;
    float cutoff;
};


// remains from ogl3
uniform LightInfo clientLight;
uniform SpotLightInfo clientSpotLight;

uniform float matRoughnessIntensity;
uniform float matSpecularIntensity;
uniform float clientShadowInfluence;
uniform float clientAmbientInfluence;

uniform sampler2D textureMap;
uniform sampler2D normalMap;
uniform sampler2DShadow shadowMap;
uniform sampler2D clientLightSample;
uniform sampler2DRect clientAuxiliaryMap;

uniform samplerCube clientSkyMap;
uniform samplerCube clientDiffuseMap;
uniform samplerCube clientSpecularMap;
uniform sampler3D clientNoiseMap;
uniform mat4 clientModelViewMatrix;
uniform mat4 clientViewMatrix;

uniform float clientMaxLightSampleLOD = 5.0f;
uniform vec3 clientLightCoefficients[10];

layout (location = 0) out vec4 FragColor;
layout (location = 1) out vec4 FragNormalDepth;
layout (location = 2) out vec4 FragPositon;

// Alt: (1.0f + cos(  length(vec2(my)) * M_PI)) / (2.0f * M_PI);
float gaussApx( float my, float sigm)
{
    float sq = sigm * sigm;
    float tmp = sq / max(EPSILON, (my*my*(sq*sq-1.0)+1.0));
    return tmp * tmp * M_INV_PI;
}

// highlights
float beckAprox(float ndl, float ndv, float Roughness)
{
    float kapxl = Roughness * Roughness * 0.5f;
    float dist = (ndl * ( 1.0 - kapxl ) + kapxl) ;
    return 1.0f / ( dist * dist);
}


 // schlick fresnel aproximation
vec3 schlickFres( float VdotH, vec3 F0)
{
    float s = pow(1.0f - VdotH, 5.0f);
    vec3 fresnel = (vec3(1.0f) - F0) * s + F0;
    return fresnel; 
}

// perhaps ward is better in this case ?
vec3 cookTorranceBrdf(vec3 Nn, vec3 Ln, vec3 Vn, vec3 Ks, float rough)
{
    vec3 Hn = normalize(Vn + Ln);
    return     schlickFres(max( 0.0, dot(Vn, Hn) ), Ks) 
            *  ( 
                      gaussApx(max( 0.0, dot(Nn, Hn) ),rough) 
                    * beckAprox( max( 0.0, dot(Nn, Ln) ), 
                                 max( 0.0, dot(Nn, Vn) ), rough) / 4.0f 
                );
}

// absolute to avoid ugly seams at normal flips 
vec3 rotateQuat( vec4 q, vec3 v ){
    return v + 2.0 * cross(q.xyz, cross(q.xyz ,v) + q.w*v);
}

void envLight(in vec3 normal, in vec3 eyeDir, in float rough, inout vec3 diffusePart, inout vec3 specPart)
{

    vec3 tLS = rotateQuat(vec4(LAMBERT_MAX,0,0,LAMBERT_MAX), normal);
    vec3 biLS = rotateQuat(vec4(0,LAMBERT_MAX,0,LAMBERT_MAX), normal);

    vec3 dp = vec3(0.0f);
    vec3 sp = vec3(0.0f);

    vec3 diffC = diffusePart;
    vec3 specC = specPart;

    float eDotN = max(EPSILON, abs( dot( eyeDir, normal ) ) );

    vec3 Ln = -reflect(eyeDir,normal);

    float nDotl = dot(normal, Ln);
    const float normalOcc = 1.3;
    float horiz = clamp( 1.0 + normalOcc * nDotl, 0.0, 1.0 );

    horiz *= horiz;
    nDotl = max( EPSILON, abs(nDotl) );

    float vdh = max( EPSILON, abs(dot(eyeDir, normal)) );
    float ndh = max( EPSILON, abs(dot(normal, normal)) );

    float ggx = gaussApx(ndh, rough) * ndh / (4.0 * vdh);

    vec3 cte = schlickFres(vdh,specC) * (beckAprox(nDotl,eDotN,rough) * vdh * nDotl / ndh );

    //  bad aprox dab  
    Ln = normalize(vsReflectRay);

    vec2 uv = 1.0f - (Ln.xy + 1.0f) / 2.0f; 
    vec2 res = textureSize(clientAuxiliaryMap);
    sp += texture(clientAuxiliaryMap, uv * res).rgb * cte * horiz;

    diffusePart = dp;
    specPart = sp;

    const float ScaleFactor = 1.0;
    const float C1 = 0.429043;
    const float C2 = 0.511664;
    const float C3 = 0.743125;
    const float C4 = 0.886227;
    const float C5 = 0.247708;

    vec3 L00  = clientLightCoefficients[0];
    vec3 L1m1 = clientLightCoefficients[1];
    vec3 L10  = clientLightCoefficients[2];

    vec3 L11  = clientLightCoefficients[3];
    vec3 L2m2 = clientLightCoefficients[4];
    vec3 L2m1 = clientLightCoefficients[5];
    vec3 L20  = clientLightCoefficients[6];
    vec3 L21  = clientLightCoefficients[7];
    vec3 L22  = clientLightCoefficients[8];

    vec3 t = normalize(tLS.zyx);
    t.x *= -1;

    // the 2014 version

    const float A0 = 1.0f;
    const float Y00 = sqrt(1 / (4.0f * M_PI));
    float Y2m2 = sqrt(15 / (4 * M_PI)) * t.x * t.y;
    float Y2m1 = sqrt(15 / (4 * M_PI)) * t.y * t.z;
    float Y21 = sqrt(15 / (4 * M_PI)) * t.x * t.z;
    float Y20 = sqrt(5 / (16 * M_PI)) * 3 * t.z * t.z - 1;
    float Y22 = sqrt(15 / (16 * M_PI)) * t.x * t.x - t.y * t.y;

    diffusePart = A0 * L00 * Y00 +
        L2m2 * Y2m2 * t +
        L2m1 * Y2m1 * t +
        L20 * Y20  * t +
        L21 * Y21 * t +
        L22 * Y22 *  t;

   diffusePart *= clientLightCoefficients[9] * diffC;

}

vec4 lampLight(in vec3 normal, in vec3 eyeDir, in float rough, in float metal, out vec3 diffusePart, out vec3 specPart)
{

    // for gpus without subs
    float hasTex = float(clientMaterial.texNum & 1);   
    vec4 texColor = vec4(vsColor * clientMaterial.Ka ,1)  * (1 - hasTex); 
    texColor += texture(textureMap, vsTexture) * hasTex;

    texColor = pow(texColor, vec4(2.2));

    vec3 diffC = texColor.rgb * (1.0f - metal);
    vec3 specC = mix(vec3(0.1), texColor.rgb, metal);

    // Point
    float isDirect = max(sign(clientLight.Position.w), 0);
    vec3 lightDir = normalize(clientLight.Position.xyz - vsPosition * isDirect);
    vec3 lightColor = clientLight.Intensity;
    float nDotL = max(dot(normal, lightDir), 0.0f);

    vec3 ctC = cookTorranceBrdf(normal,lightDir,eyeDir,specC, rough);

    vec3 lightContrib = nDotL * ( (diffC + ctC) * lightColor);

    // Spot
    lightDir = normalize(clientSpotLight.position.xyz - vsPosition);

    float angle = acos( dot(-lightDir, clientSpotLight.direction));
    float cutoff = radians( clamp ( clientSpotLight.cutoff, 0.0f, 90.0f ));

    lightColor = clientSpotLight.intensity;
    nDotL = max(dot(normal, lightDir), 0.0f);
    ctC = cookTorranceBrdf(normal,lightDir,eyeDir,specC, rough);
    lightContrib += nDotL * ( (diffC + ctC) * lightColor) * float(angle < cutoff);

    diffusePart = diffC;
    specPart = specC;

    return vec4(lightContrib, 1);
}

void main() {

    vec3 diffusePart = vec3(0);
    vec3 specPart = vec3(0);

    vec3 normal = normalize(vsNormal);
    vec3 eyeDir = normalize(clientEye - vsPosition);
    float rough = clamp(matRoughnessIntensity, EPSILON, 1.0f);
    float metal = clamp(matSpecularIntensity, EPSILON, 1.0f);;

    vec4 col = lampLight(normal, eyeDir, rough, metal, diffusePart, specPart);

    envLight(normal, eyeDir, rough, diffusePart, specPart);
    col.rgb += (diffusePart + specPart) * clientAmbientInfluence;

    FragColor = vec4(col.rgb ,1.0f);

    // no deferrred
    // FragNormalDepth = vec4(normal, distance(clientEye, vsPosition));
    // FragPositon = vec4(vsPosition,1.0);
}