/*
 * Fragment shader for cube demo
 */
#version 400
#extension GL_ARB_separate_shader_objects : enable
#extension GL_ARB_shading_language_420pack : enable

layout (location = 0) out vec4 uFragColor;
void main()
{
   uFragColor = vec4(1.0, 0.0, 0.0, 1.0); //texture(tex, texcoord.xy);
}
