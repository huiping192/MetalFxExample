//
//  ContentView.swift
//  metalfxsample
//
//  Created by 郭 輝平 on 2024/09/28.
//

import SwiftUI
import AVFoundation
struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  
  var body: some View {
    VStack {
      ZStack {
        SampleBufferView(sampleBuffer: $viewModel.originalSampleBuffer)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .mask(
            GeometryReader { geometry in
              HStack(spacing: 0) {
                Rectangle()
                  .frame(width: geometry.size.width * viewModel.splitPosition)
                Rectangle().fill(Color.clear)
              }
            }
          )
        
        SampleBufferView(sampleBuffer: $viewModel.processedSampleBuffer)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .mask(
            GeometryReader { geometry in
              HStack(spacing: 0) {
                Rectangle().fill(Color.clear)
                  .frame(width: geometry.size.width * viewModel.splitPosition)
                Rectangle()
              }
            }
          )
        
        // 添加分界线
        GeometryReader { geometry in
          Rectangle()
            .fill(Color.white)
            .frame(width: 2)
            .position(x: geometry.size.width * viewModel.splitPosition, y: geometry.size.height / 2)
        }
        
        // 添加标签
        GeometryReader { geometry in
          VStack {
            Text("Original")
              .foregroundColor(.white)
              .padding(5)
              .background(Color.black.opacity(0.7))
              .cornerRadius(5)
              .position(x: geometry.size.width * viewModel.splitPosition / 2, y: 20)
            
            Text("Processed")
              .foregroundColor(.white)
              .padding(5)
              .background(Color.black.opacity(0.7))
              .cornerRadius(5)
              .position(x: geometry.size.width * (1 + viewModel.splitPosition) / 2, y: 20)
          }
        }
      }
      .aspectRatio(16/9, contentMode: .fit)
      .border(Color.gray, width: 1)
      
      Button(action: {
        viewModel.toggleCamera()
      }) {
        Text(viewModel.isCameraRunning ? "Stop Camera" : "Start Camera")
      }
      .padding()
      
      Slider(value: $viewModel.splitPosition, in: 0...1)
        .padding()
    }
  }
}


#if os(iOS)
struct SampleBufferView: UIViewRepresentable {
  @Binding var sampleBuffer: CMSampleBuffer?
  
  func makeUIView(context: Context) -> SampleBufferDisplayView {
    SampleBufferDisplayView()
  }
  
  func updateUIView(_ uiView: SampleBufferDisplayView, context: Context) {
    if let sampleBuffer = sampleBuffer {
      uiView.displaySampleBuffer(sampleBuffer)
    }
  }
}

class SampleBufferDisplayView: UIView {
  private let displayLayer = AVSampleBufferDisplayLayer()
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    setupDisplayLayer()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupDisplayLayer()
  }
  
  private func setupDisplayLayer() {
    displayLayer.videoGravity = .resizeAspect
    layer.addSublayer(displayLayer)
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    displayLayer.frame = bounds
  }
  
  func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    displayLayer.enqueue(sampleBuffer)
  }
}
#elseif os(macOS)
struct SampleBufferView: NSViewRepresentable {
  @Binding var sampleBuffer: CMSampleBuffer?
  
  func makeNSView(context: Context) -> SampleBufferDisplayView {
    SampleBufferDisplayView()
  }
  
  func updateNSView(_ nsView: SampleBufferDisplayView, context: Context) {
    if let sampleBuffer = sampleBuffer {
      nsView.displaySampleBuffer(sampleBuffer)
    }
  }
}

class SampleBufferDisplayView: NSView {
  private let displayLayer = AVSampleBufferDisplayLayer()
  
  override init(frame: NSRect) {
    super.init(frame: frame)
    setupDisplayLayer()
  }
  
  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupDisplayLayer()
  }
  
  private func setupDisplayLayer() {
    displayLayer.videoGravity = .resizeAspect
    layer = CALayer()
    layer?.addSublayer(displayLayer)
    wantsLayer = true
  }
  
  override func layout() {
    super.layout()
    displayLayer.frame = bounds
  }
  
  func displaySampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    displayLayer.enqueue(sampleBuffer)
  }
}
#endif

class ContentViewModel: ObservableObject {
  @Published var originalSampleBuffer: CMSampleBuffer?
  @Published var processedSampleBuffer: CMSampleBuffer?
  @Published var isCameraRunning = false
  
  @Published var splitPosition: Double = 0.5 // 默认在中间
  
  private let cameraManager = CameraManager()
  private let imageProcessor: MetalImageProcessor?
  
  init() {
    imageProcessor = MetalImageProcessor()
    
    setupCameraCallback()
  }
  
  private func setupCameraCallback() {
    cameraManager.setSampleBufferCallback { [weak self] sampleBuffer in
      self?.handleSampleBuffer(sampleBuffer)
    }
  }
  
  private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    DispatchQueue.main.async {
      self.originalSampleBuffer = sampleBuffer
      if let processedBuffer = self.imageProcessor?.processBuffer(sampleBuffer) {
        self.processedSampleBuffer = processedBuffer
      }
    }
  }
  
  func toggleCamera() {
    if isCameraRunning {
      cameraManager.stopRunning()
    } else {
      cameraManager.startRunning()
    }
    isCameraRunning.toggle()
  }
}
