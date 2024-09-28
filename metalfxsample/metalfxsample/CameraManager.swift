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
    
    guard let device = AVCaptureDevice.default(for: .video) else { return }
    
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
      
    } catch {
      print("Failed to set up capture session: \(error)")
    }
  }
  
  func startRunning() {
    captureSession?.startRunning()
  }
  
  func stopRunning() {
    captureSession?.stopRunning()
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
