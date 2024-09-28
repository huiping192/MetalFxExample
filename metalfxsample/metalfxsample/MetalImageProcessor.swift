//
//  MetalImageProcessor.swift
//  metalfxsample
//
//  Created by 郭 輝平 on 2024/09/28.
//

import MetalKit
import AVFoundation
import MetalFX
import Metal

class MetalImageProcessor {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private var spatialScaler: MTLFXSpatialScaler?
  private var textureCache: CVMetalTextureCache?
  
  private var inputWidth: Int?
  private var inputHeight: Int?
  private var outputWidth: Int? {
    if let inputWidth {
      return Int(Double(inputWidth) * 1.5)
    }
    return nil
  }
  private var outputHeight: Int? {
    if let inputHeight {
      return Int(Double(inputHeight) * 1.5)
    }
    return nil
  }
  private let colorPixelFormat: MTLPixelFormat = .bgra8Unorm
  
  init?() {
    guard let device = MTLCreateSystemDefaultDevice(),
          let commandQueue = device.makeCommandQueue() else {
      return nil
    }
    self.device = device
    self.commandQueue = commandQueue
    
    setupTextureCache()
  }
  
  private func setupSpatialScaler() {
    guard let inputWidth, let inputHeight, let outputWidth, let outputHeight else {
      print("The spatial scaler effect is not usable!")
      return
    }
    let desc = MTLFXSpatialScalerDescriptor()
    desc.inputWidth = inputWidth
    desc.inputHeight = inputHeight
    desc.outputWidth = outputWidth
    desc.outputHeight = outputHeight
    desc.colorTextureFormat = colorPixelFormat
    desc.outputTextureFormat = colorPixelFormat
    desc.colorProcessingMode = .perceptual
    
    guard let spatialScaler = desc.makeSpatialScaler(device: device) else {
      print("The spatial scaler effect is not usable!")
      return
    }
    
    self.spatialScaler = spatialScaler
  }
  
  private func setupTextureCache() {
    var textureCache: CVMetalTextureCache?
    if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) != kCVReturnSuccess {
      print("Unable to allocate texture cache")
    } else {
      self.textureCache = textureCache
    }
  }
  
  private func makeTextureFromCVPixelBuffer(_ pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    
    var cvTextureOut: CVMetalTexture?
    CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)
    
    guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
      print("Failed to create metal texture from pixel buffer")
      return nil
    }
    
    return texture
  }
  
  private func copyTextureToPixelBuffer(texture: MTLTexture, pixelBuffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    
    guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      print("Failed to get pixel buffer base address")
      return
    }
    
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
    
    texture.getBytes(pixelBufferBytes,
                     bytesPerRow: bytesPerRow,
                     from: region,
                     mipmapLevel: 0)
  }
  
  func processBuffer(_ inputBuffer: CMSampleBuffer) -> MTLTexture? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(inputBuffer) else {
      print("Failed to get pixel buffer from input sample buffer")
      return nil
    }
    
    let inputWidth = CVPixelBufferGetWidth(pixelBuffer)
    let inputHeight = CVPixelBufferGetHeight(pixelBuffer)
    let inputPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    
    if spatialScaler == nil {
      self.inputWidth = inputWidth
      self.inputHeight = inputHeight
      setupSpatialScaler()
    }
    
    guard let spatialScaler = self.spatialScaler else {
      print("Spatial scaler is not initialized")
      return nil
    }
    
    // Create input texture
    guard let inputTexture = makeTextureFromCVPixelBuffer(pixelBuffer, textureFormat: colorPixelFormat) else {
      print("Failed to create input texture")
      return nil
    }
    
    // Create output texture
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: colorPixelFormat,
      width: outputWidth!,
      height: outputHeight!,
      mipmapped: false)
    textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    textureDescriptor.storageMode = .private
    
    guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
      print("Failed to create output texture")
      return nil
    }
    
    let finalOutputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: colorPixelFormat,
      width: outputWidth!,
      height: outputHeight!,
      mipmapped: false)
    finalOutputDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    finalOutputDescriptor.storageMode = .shared
    
    guard let finalOutputTexture = device.makeTexture(descriptor: finalOutputDescriptor) else {
      print("Failed to create final output texture")
      return nil
    }
    
    // Create command buffer
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      print("Failed to create command buffer")
      return nil
    }
    
    spatialScaler.colorTexture = inputTexture
    spatialScaler.outputTexture = outputTexture
    spatialScaler.encode(commandBuffer: commandBuffer)
    
//    let blitEncoder = commandBuffer.makeBlitCommandEncoder()
//    blitEncoder?.copy(from: outputTexture, to: finalOutputTexture)
//    blitEncoder?.endEncoding()
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    return  outputTexture
    
    // Create output pixel buffer
//    var newPixelBuffer: CVPixelBuffer?
//    let pixelBufferAttributes = [
//      kCVPixelBufferWidthKey: outputWidth!,
//      kCVPixelBufferHeightKey: outputHeight!,
//      kCVPixelBufferPixelFormatTypeKey: inputPixelFormat // Use the same format as input
//    ] as CFDictionary
//    
//    CVPixelBufferCreate(kCFAllocatorDefault, outputWidth!, outputHeight!, inputPixelFormat, pixelBufferAttributes, &newPixelBuffer)
//    
//    if let newPixelBuffer = newPixelBuffer {
//      copyTextureToPixelBuffer(texture: finalOutputTexture, pixelBuffer: newPixelBuffer)
//      return makeSampleBuffer(pixelBuffer: newPixelBuffer, originBuffer: inputBuffer)
//    } else {
//      print("Failed to create new pixel buffer")
//    }
    
//    return nil
  }
  
  
  func makeSampleBuffer(pixelBuffer: CVPixelBuffer, originBuffer: CMSampleBuffer) -> CMSampleBuffer? {
    // Create new sample buffer
    var newSampleBuffer: CMSampleBuffer?
    var timingInfo = CMSampleTimingInfo()
    CMSampleBufferGetSampleTimingInfo(originBuffer, at: 0, timingInfoOut: &timingInfo)
    
    var formatDescription: CMFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
    
    guard let formatDescription = formatDescription else {
      print("Failed to create format description")
      return nil
    }
    
    CMSampleBufferCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: formatDescription,
      sampleTiming: &timingInfo,
      sampleBufferOut: &newSampleBuffer)
    
    return newSampleBuffer
  }
}


#if os(iOS)
func uiImage(from sampleBuffer: CMSampleBuffer) -> UIImage? {
  guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
    print("Failed to get pixel buffer from sample buffer")
    return nil
  }
  
  let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
  let context = CIContext()
  
  guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
    print("Failed to create CGImage")
    return nil
  }
  
  // 注意：这里的方向可能需要根据实际情况调整
  return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
}


#endif
