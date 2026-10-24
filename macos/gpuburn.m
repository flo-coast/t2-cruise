// gpuburn: keep the Radeon busy with a Metal compute kernel for N seconds.
// build: clang -O2 -fobjc-arc -framework Metal -framework Foundation -o gpuburn gpuburn.m
// usage: gpuburn <seconds>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static NSString *src =
    @"#include <metal_stdlib>\nusing namespace metal;\n"
     "kernel void burn(device float *o [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
     "  float a = i * 0.001f, b = 1.0001f;\n"
     "  for (int k = 0; k < 4096; k++) { a = fma(a, b, 0.5f); b = fma(b, a, -0.25f); a = sin(a) + cos(b); }\n"
     "  o[i] = a + b;\n}\n";

int main(int argc, char **argv) {
    @autoreleasepool {
        double secs = argc > 1 ? atof(argv[1]) : 60;
        id<MTLDevice> dev = nil;
        for (id<MTLDevice> d in MTLCopyAllDevices())
            if (!d.lowPower) dev = d;  // the discrete Radeon, not the Intel iGPU
        if (!dev) { fprintf(stderr, "no discrete GPU\n"); return 1; }
        printf("GPU: %s\n", dev.name.UTF8String);
        NSError *err = nil;
        id<MTLLibrary> lib = [dev newLibraryWithSource:src options:nil error:&err];
        id<MTLComputePipelineState> ps =
            [dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"burn"] error:&err];
        if (!ps) { fprintf(stderr, "%s\n", err.description.UTF8String); return 1; }
        NSUInteger n = 1 << 20;
        id<MTLBuffer> buf = [dev newBufferWithLength:n * sizeof(float) options:MTLResourceStorageModePrivate];
        id<MTLCommandQueue> q = [dev newCommandQueue];
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:secs];
        while ([end timeIntervalSinceNow] > 0) {
            id<MTLCommandBuffer> cb = [q commandBuffer];
            id<MTLComputeCommandEncoder> e = [cb computeCommandEncoder];
            [e setComputePipelineState:ps];
            [e setBuffer:buf offset:0 atIndex:0];
            [e dispatchThreads:MTLSizeMake(n, 1, 1) threadsPerThreadgroup:MTLSizeMake(ps.maxTotalThreadsPerThreadgroup, 1, 1)];
            [e endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
        }
    }
    return 0;
}
