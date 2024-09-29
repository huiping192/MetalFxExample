//
//  ContentView.swift
//  metalfxsample
//
//  Created by 郭 輝平 on 2024/09/28.
//

import SwiftUI
import AVFoundation
import MetalKit

struct ContentView: View {
  @StateObject private var viewModel = ContentViewModel()
  @State private var showControls = true
  
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // 图像层
        ZStack {
          SampleBufferView(sampleBuffer: $viewModel.originalSampleBuffer)
            .mask(
              HStack(spacing: 0) {
                Rectangle()
                  .frame(width: geometry.size.width * viewModel.splitPosition)
                Rectangle().fill(Color.clear)
              }
            )
          
          SampleBufferView(sampleBuffer: $viewModel.processedSampleBuffer)
            .mask(
              HStack(spacing: 0) {
                Rectangle().fill(Color.clear)
                  .frame(width: geometry.size.width * viewModel.splitPosition)
                Rectangle()
              }
            )
          
          // 分界线
          Rectangle()
            .fill(Color.white)
            .frame(width: 1)
            .position(x: geometry.size.width * viewModel.splitPosition, y: geometry.size.height / 2)
        }
        .edgesIgnoringSafeArea(.all)
        
        // 控制层
        VStack {
          if showControls {
            // 标签
            HStack {
              Text("Original")
                .foregroundColor(.white)
                .padding(5)
                .background(Color.black.opacity(0.7))
                .cornerRadius(5)
                .padding(.leading)
              
              Spacer()
              
              Text("Processed")
                .foregroundColor(.white)
                .padding(5)
                .background(Color.black.opacity(0.7))
                .cornerRadius(5)
                .padding(.trailing)
            }
            .padding(.top, geometry.safeAreaInsets.top)
            
            Spacer()
            
            // 控制按钮和滑块
            VStack {
              Slider(value: $viewModel.splitPosition, in: 0...1)
                .padding()
              Button(action: {
                viewModel.toggleCamera()
              }) {
                Text(viewModel.isCameraRunning ? "Stop" : "Start")
                  .padding()
                  .background(Color.blue)
                  .foregroundColor(.white)
                  .cornerRadius(10)
              }
            }
            .cornerRadius(10)
            .padding()
          }
        }
      }
    }
    .statusBar(hidden: true)
    .onTapGesture {
      withAnimation {
        showControls.toggle()
      }
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
    displayLayer.videoGravity = .resizeAspectFill
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
    Task {
      if isCameraRunning {
        cameraManager.stopRunning()
      } else {
        cameraManager.startRunning()
      }
    }
    isCameraRunning.toggle()
  }
}


struct MetalView: UIViewRepresentable {
  var texture: MTLTexture?
  
  func makeUIView(context: Context) -> MTKView {
    let mtkView = MTKView()
    mtkView.device = MTLCreateSystemDefaultDevice()
    mtkView.delegate = context.coordinator
    mtkView.enableSetNeedsDisplay = true
    mtkView.framebufferOnly = false
    mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.contentMode = .scaleAspectFit
    return mtkView
  }
  
  func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.texture = texture
    uiView.setNeedsDisplay()
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  class Coordinator: NSObject, MTKViewDelegate {
    var parent: MetalView
    var texture: MTLTexture?
    var pipelineState: MTLRenderPipelineState?
    var commandQueue: MTLCommandQueue?
    
    init(_ parent: MetalView) {
      self.parent = parent
      super.init()
      createPipelineState()
    }
    
    func createPipelineState() {
      guard let device = MTLCreateSystemDefaultDevice() else { return }
      commandQueue = device.makeCommandQueue()
      
      let library = device.makeDefaultLibrary()
      let vertexFunction = library?.makeFunction(name: "vertexShader")
      let fragmentFunction = library?.makeFunction(name: "fragmentShader")
      
      let pipelineDescriptor = MTLRenderPipelineDescriptor()
      pipelineDescriptor.vertexFunction = vertexFunction
      pipelineDescriptor.fragmentFunction = fragmentFunction
      pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      
      do {
        pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
      } catch {
        print("Unable to create pipeline state: \(error)")
      }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
      guard let texture = texture,
            let pipelineState = pipelineState,
            let commandQueue = commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let descriptor = view.currentRenderPassDescriptor,
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
        return
      }
      
      renderEncoder.setRenderPipelineState(pipelineState)
      renderEncoder.setFragmentTexture(texture, index: 0)
      renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
      renderEncoder.endEncoding()
      
      if let drawable = view.currentDrawable {
        commandBuffer.present(drawable)
      }
      commandBuffer.commit()
    }
  }
}
