//
//  Untitled.swift
//  metalfxsample
//
//  Created by 郭 輝平 on 2024/09/28.
//
import AVFoundation

class CameraManager: NSObject {
  typealias SampleBufferCallback = (CMSampleBuffer) -> Void
  
  private var captureSession: AVCaptureSession?
  private let outputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
  private var sampleBufferCallback: SampleBufferCallback?
  
  override init() {
    super.init()
    setupCaptureSession()
  }
  
  private func setupCaptureSession() {
    captureSession = AVCaptureSession()
    captureSession?.sessionPreset = .hd1280x720 // Set to 720p
    
    // 获取前置摄像头
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
      print("Failed to get front camera")
      return
    }
    
    do {
      let input = try AVCaptureDeviceInput(device: device)
      if captureSession?.canAddInput(input) == true {
        captureSession?.addInput(input)
      }
      
      let output = AVCaptureVideoDataOutput()
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      output.setSampleBufferDelegate(self, queue: outputQueue)
      if captureSession?.canAddOutput(output) == true {
        captureSession?.addOutput(output)
      }
      
      // 设置视频方向为竖直
      if let connection = output.connection(with: .video) {
        if connection.isVideoOrientationSupported {
          connection.videoOrientation = .portrait
        }
        
        // 如果需要镜像前置摄像头的画面（通常需要）
        if connection.isVideoMirroringSupported {
          connection.isVideoMirrored = true
        }
      }
      
    } catch {
      print("Failed to set up capture session: \(error)")
    }
  }
  
  func startRunning() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.captureSession?.startRunning()
    }
  }
  
  func stopRunning() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.captureSession?.stopRunning()
    }
  }
  
  func setSampleBufferCallback(_ callback: @escaping SampleBufferCallback) {
    sampleBufferCallback = callback
  }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    sampleBufferCallback?(sampleBuffer)
  }
}
