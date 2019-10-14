/*
Copyright © 2019 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

Abstract:
Metal compute shader that translates depth values to grayscale RGB values.
*/

#include <metal_stdlib>
using namespace metal;

struct converterParameters {
    float offset;
    float range;
};

// Compute kernel
kernel void depthToGrayscale(texture2d<float, access::read>  inputTexture      [[ texture(0) ]],
                             texture2d<float, access::write> outputTexture     [[ texture(1) ]],
                             constant converterParameters& converterParameters [[ buffer(0) ]],
                             uint2 gid [[ thread_position_in_grid ]])
{
    // Don't read or write outside of the texture.
    if ((gid.x >= inputTexture.get_width()) || (gid.y >= inputTexture.get_height())) {
        return;
    }
    
    float depth = inputTexture.read(gid).x;
    
    // Normalize the value between 0 and 1.
    depth = (depth - converterParameters.offset) / (converterParameters.range);
    
    float4 outputColor = float4(float3(depth), 1.0);
    
    outputTexture.write(outputColor, gid);
}
