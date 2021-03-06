target triple = "x86_64-unknown-unknown"

; RUN: llc < %s -march=x86-64 -mattr=+avx | FileCheck %s

; When extracting multiple consecutive elements from a larger
; vector into a smaller one, do it efficiently. We should use
; an EXTRACT_SUBVECTOR node internally rather than a bunch of
; single element extractions.

; Extracting the low elements only requires using the right kind of store.
define void @low_v8f32_to_v4f32(<8 x float> %v, <4 x float>* %ptr) {
  %ext0 = extractelement <8 x float> %v, i32 0
  %ext1 = extractelement <8 x float> %v, i32 1
  %ext2 = extractelement <8 x float> %v, i32 2
  %ext3 = extractelement <8 x float> %v, i32 3
  %ins0 = insertelement <4 x float> undef, float %ext0, i32 0
  %ins1 = insertelement <4 x float> %ins0, float %ext1, i32 1
  %ins2 = insertelement <4 x float> %ins1, float %ext2, i32 2
  %ins3 = insertelement <4 x float> %ins2, float %ext3, i32 3
  store <4 x float> %ins3, <4 x float>* %ptr, align 16
  ret void

; CHECK-LABEL: low_v8f32_to_v4f32
; CHECK: vmovaps
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

; Extracting the high elements requires just one AVX instruction.
define void @high_v8f32_to_v4f32(<8 x float> %v, <4 x float>* %ptr) {
  %ext0 = extractelement <8 x float> %v, i32 4
  %ext1 = extractelement <8 x float> %v, i32 5
  %ext2 = extractelement <8 x float> %v, i32 6
  %ext3 = extractelement <8 x float> %v, i32 7
  %ins0 = insertelement <4 x float> undef, float %ext0, i32 0
  %ins1 = insertelement <4 x float> %ins0, float %ext1, i32 1
  %ins2 = insertelement <4 x float> %ins1, float %ext2, i32 2
  %ins3 = insertelement <4 x float> %ins2, float %ext3, i32 3
  store <4 x float> %ins3, <4 x float>* %ptr, align 16
  ret void

; CHECK-LABEL: high_v8f32_to_v4f32
; CHECK: vextractf128
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

; Make sure element type doesn't alter the codegen. Note that
; if we were actually using the vector in this function and
; have AVX2, we should generate vextracti128 (the int version).
define void @high_v8i32_to_v4i32(<8 x i32> %v, <4 x i32>* %ptr) {
  %ext0 = extractelement <8 x i32> %v, i32 4
  %ext1 = extractelement <8 x i32> %v, i32 5
  %ext2 = extractelement <8 x i32> %v, i32 6
  %ext3 = extractelement <8 x i32> %v, i32 7
  %ins0 = insertelement <4 x i32> undef, i32 %ext0, i32 0
  %ins1 = insertelement <4 x i32> %ins0, i32 %ext1, i32 1
  %ins2 = insertelement <4 x i32> %ins1, i32 %ext2, i32 2
  %ins3 = insertelement <4 x i32> %ins2, i32 %ext3, i32 3
  store <4 x i32> %ins3, <4 x i32>* %ptr, align 16
  ret void

; CHECK-LABEL: high_v8i32_to_v4i32
; CHECK: vextractf128
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

; Make sure that element size doesn't alter the codegen.
define void @high_v4f64_to_v2f64(<4 x double> %v, <2 x double>* %ptr) {
  %ext0 = extractelement <4 x double> %v, i32 2
  %ext1 = extractelement <4 x double> %v, i32 3
  %ins0 = insertelement <2 x double> undef, double %ext0, i32 0
  %ins1 = insertelement <2 x double> %ins0, double %ext1, i32 1
  store <2 x double> %ins1, <2 x double>* %ptr, align 16
  ret void

; CHECK-LABEL: high_v4f64_to_v2f64
; CHECK: vextractf128
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

; PR25320 Make sure that a widened (possibly legalized) vector correctly zero-extends upper elements.
; FIXME - Ideally these should just call VMOVD/VMOVQ/VMOVSS/VMOVSD

define void @legal_vzmovl_2i32_8i32(<2 x i32>* %in, <8 x i32>* %out) {
  %ld = load <2 x i32>, <2 x i32>* %in, align 8
  %ext = extractelement <2 x i32> %ld, i64 0
  %ins = insertelement <8 x i32> <i32 undef, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0, i32 0>, i32 %ext, i64 0
  store <8 x i32> %ins, <8 x i32>* %out, align 32
  ret void

; CHECK-LABEL: legal_vzmovl_2i32_8i32
; CHECK: vpmovzxdq {{.*#+}} xmm0 = mem[0],zero,mem[1],zero
; CHECK-NEXT: vxorps %ymm1, %ymm1, %ymm1
; CHECK-NEXT: vblendps {{.*#+}} ymm0 = ymm0[0],ymm1[1,2,3,4,5,6,7]
; CHECK-NEXT: vmovaps %ymm0, (%rsi)
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

define void @legal_vzmovl_2i64_4i64(<2 x i64>* %in, <4 x i64>* %out) {
  %ld = load <2 x i64>, <2 x i64>* %in, align 8
  %ext = extractelement <2 x i64> %ld, i64 0
  %ins = insertelement <4 x i64> <i64 undef, i64 0, i64 0, i64 0>, i64 %ext, i64 0
  store <4 x i64> %ins, <4 x i64>* %out, align 32
  ret void

; CHECK-LABEL: legal_vzmovl_2i64_4i64
; CHECK: vmovupd (%rdi), %xmm0
; CHECK-NEXT: vxorpd %ymm1, %ymm1, %ymm1
; CHECK-NEXT: vblendpd {{.*#+}} ymm0 = ymm0[0],ymm1[1,2,3]
; CHECK-NEXT: vmovapd %ymm0, (%rsi)
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

define void @legal_vzmovl_2f32_8f32(<2 x float>* %in, <8 x float>* %out) {
  %ld = load <2 x float>, <2 x float>* %in, align 8
  %ext = extractelement <2 x float> %ld, i64 0
  %ins = insertelement <8 x float> <float undef, float 0.0, float 0.0, float 0.0, float 0.0, float 0.0, float 0.0, float 0.0>, float %ext, i64 0
  store <8 x float> %ins, <8 x float>* %out, align 32
  ret void

; CHECK-LABEL: legal_vzmovl_2f32_8f32
; CHECK: vmovq {{.*#+}} xmm0 = mem[0],zero
; CHECK-NEXT: vxorps %ymm1, %ymm1, %ymm1
; CHECK-NEXT: vblendps {{.*#+}} ymm0 = ymm0[0],ymm1[1,2,3,4,5,6,7]
; CHECK-NEXT: vmovaps %ymm0, (%rsi)
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}

define void @legal_vzmovl_2f64_4f64(<2 x double>* %in, <4 x double>* %out) {
  %ld = load <2 x double>, <2 x double>* %in, align 8
  %ext = extractelement <2 x double> %ld, i64 0
  %ins = insertelement <4 x double> <double undef, double 0.0, double 0.0, double 0.0>, double %ext, i64 0
  store <4 x double> %ins, <4 x double>* %out, align 32
  ret void

; CHECK-LABEL: legal_vzmovl_2f64_4f64
; CHECK: vmovupd (%rdi), %xmm0
; CHECK-NEXT: vxorpd %ymm1, %ymm1, %ymm1
; CHECK-NEXT: vblendpd {{.*#+}} ymm0 = ymm0[0],ymm1[1,2,3]
; CHECK-NEXT: vmovapd %ymm0, (%rsi)
; CHECK-NEXT: vzeroupper
; CHECK-NEXT: retq
}
