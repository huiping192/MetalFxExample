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
//    let pba =  convertMTLTextureToCVPixelBuffer(texture: inputTexture)!
//    return convertCVPixelBufferToCMSampleBuffer(pixelBuffer: pba, originalSampleBuffer: inputBuffer)
    
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
    
    let blitEncoder = commandBuffer.makeBlitCommandEncoder()
    blitEncoder?.copy(from: outputTexture, to: finalOutputTexture)
    blitEncoder?.endEncoding()
    
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    let pb = convertMTLTextureToCVPixelBuffer(texture: finalOutputTexture)    
    return convertCVPixelBufferToCMSampleBuffer(pixelBuffer: pb!, originalSampleBuffer: inputBuffer)
  }
  
  
  func convertCVPixelBufferToCMSampleBuffer(pixelBuffer: CVPixelBuffer, originalSampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
    
    // 从原始SampleBuffer获取timing信息
    var timingInfo = CMSampleTimingInfo()
    var count: CMItemCount = 0
    CMSampleBufferGetSampleTimingInfoArray(originalSampleBuffer, entryCount: 1, arrayToFill: &timingInfo, entriesNeededOut: &count)

    return CMSampleBuffer.make(from: pixelBuffer, formatDescription: CMFormatDescription.make(from: pixelBuffer)!, timingInfo: &timingInfo)
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
  
  return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
}

func converToImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
  let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
  let context = CIContext()
  
  guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
    print("Failed to create CGImage")
    return nil
  }
  
  return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
}



#endif


func convertMTLTextureToCVPixelBuffer(texture: MTLTexture) -> CVPixelBuffer? {
  let width = texture.width
      let height = texture.height
      
      var pixelBuffer: CVPixelBuffer?
      let attributes = [
          kCVPixelBufferMetalCompatibilityKey: true,
          kCVPixelBufferIOSurfacePropertiesKey: [:]
      ] as CFDictionary
      
      let status = CVPixelBufferCreate(
          kCFAllocatorDefault,
          width,
          height,
          kCVPixelFormatType_32BGRA,
          attributes,
          &pixelBuffer
      )
      
      guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else {
          print("Failed to create pixel buffer")
          return nil
      }
      
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
      
      guard let pixelBufferBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
          print("Failed to get pixel buffer base address")
          return nil
      }
      
      let region = MTLRegionMake2D(0, 0, width, height)
      texture.getBytes(
          pixelBufferBaseAddress,
          bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
          from: region,
          mipmapLevel: 0
      )
      
      // 设置额外的属性
      CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
      CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
      CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
      
      return pixelBuffer
}


func convertCVPixelBufferToUIImage(pixelBuffer: CVPixelBuffer) -> UIImage? {
  CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
  defer {
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
  }
  
  let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
  
  guard let context = CGContext(data: baseAddress,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue) else {
    print("Failed to create CGContext")
    return nil
  }
  
  guard let cgImage = context.makeImage() else {
    print("Failed to create CGImage")
    return nil
  }
  
  let image = UIImage(cgImage: cgImage)
  return image
}


extension CMFormatDescription {
  static func make(from pixelBuffer: CVPixelBuffer) -> CMFormatDescription? {
    var formatDescription: CMFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
    return formatDescription
  }
}

extension CMSampleBuffer {
  static func make(from pixelBuffer: CVPixelBuffer, formatDescription: CMFormatDescription, timingInfo: inout CMSampleTimingInfo) -> CMSampleBuffer? {
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil,
                                       refcon: nil, formatDescription: formatDescription, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
    return sampleBuffer
  }
}
