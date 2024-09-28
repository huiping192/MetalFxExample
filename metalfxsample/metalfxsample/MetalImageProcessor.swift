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
  
  func processBuffer(_ inputBuffer: CMSampleBuffer) -> CMSampleBuffer? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(inputBuffer) else {
      return nil
    }
    
    if spatialScaler == nil {
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      self.inputWidth = width
      self.inputHeight = height
      setupSpatialScaler()
    }
    
    guard  let spatialScaler = self.spatialScaler else {
      return nil
    }
    
    // Create input texture
    guard let inputTexture = makeTextureFromCVPixelBuffer(pixelBuffer, textureFormat: colorPixelFormat) else {
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
      return nil
    }
    let finalOutputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: colorPixelFormat,
      width: outputWidth!,
      height: outputHeight!,
      mipmapped: false)
    finalOutputDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]  // Add .renderTarget
    finalOutputDescriptor.storageMode = .shared
    
    guard let finalOutputTexture = device.makeTexture(descriptor: finalOutputDescriptor) else {
      return nil
    }
    
    // Create command buffer
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      return nil
    }
    
    spatialScaler.colorTexture = inputTexture
    spatialScaler.outputTexture = outputTexture
    // Encode scaling operation
    spatialScaler.encode(commandBuffer: commandBuffer)
    
    
    // Copy from private texture to shared texture
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()
    blitEncoder?.copy(from: outputTexture, to: finalOutputTexture)
    blitEncoder?.endEncoding()
    
    // Execute command buffer
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    // Create output pixel buffer
    var newPixelBuffer: CVPixelBuffer?
    let pixelBufferAttributes = [
      kCVPixelBufferWidthKey: outputWidth,
      kCVPixelBufferHeightKey: outputHeight,
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
    ] as CFDictionary
    
    CVPixelBufferCreate(kCFAllocatorDefault, outputWidth!, outputHeight!, kCVPixelFormatType_32BGRA, pixelBufferAttributes, &newPixelBuffer)
    
    if let newPixelBuffer = newPixelBuffer {
      copyTextureToPixelBuffer(texture: finalOutputTexture, pixelBuffer: newPixelBuffer)
      
      // Create new sample buffer
      var newSampleBuffer: CMSampleBuffer?
      var timingInfo = CMSampleTimingInfo()
      CMSampleBufferGetSampleTimingInfo(inputBuffer, at: 0, timingInfoOut: &timingInfo)
      
      var formatDescription: CMFormatDescription?
      CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: newPixelBuffer, formatDescriptionOut: &formatDescription)
      
      if let formatDescription = formatDescription {
        CMSampleBufferCreateForImageBuffer(
          allocator: kCFAllocatorDefault,
          imageBuffer: newPixelBuffer,
          dataReady: true,
          makeDataReadyCallback: nil,
          refcon: nil,
          formatDescription: formatDescription,
          sampleTiming: &timingInfo,
          sampleBufferOut: &newSampleBuffer)
      }
      
      return newSampleBuffer
    }
    
    return nil
  }
}
