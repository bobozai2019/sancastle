Shader hash b3275c56-1ae09260-5cd312d4-1982f6a2

ps_5_0
      dcl_globalFlags refactoringAllowed, skipOptimisation
      dcl_sampler _Sampler0 (s0), mode_default
      dcl_resource_texture2d (float,float,float,float) _MainTex (t0)
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw

      c:\projects\unity\dunity\runtime\gfxdevice\d3d12\internalshaders\internalshaders.hlsl:30 - DrawQuadPS()
      return _MainTex.Sample(_Sampler0, Input.TexCoord);
   0: sample_indexable(texture2d)(float,float,float,float) o0.xyzw, v1.xyxx, _MainTex.xyzw, _Sampler0
   1: ret
