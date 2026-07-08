import AppKit
@preconcurrency import CoreVideo
import MetalKit
import QuartzCore
import SwiftUI

struct EdgeMotionBackdropView: NSViewRepresentable {
    let preferences: MotionBackdropPreferences

    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> EdgeMotionMetalView {
        EdgeMotionMetalView(settings: renderSettings)
    }

    func updateNSView(_ nsView: EdgeMotionMetalView, context: Context) {
        nsView.apply(settings: renderSettings)
    }

    private var renderSettings: EdgeMotionRenderSettings {
        EdgeMotionRenderSettings(
            mode: preferences.mode,
            speed: preferences.speed,
            intensity: preferences.intensity,
            isPaused: preferences.isPaused,
            isLight: colorScheme == .light,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }
}

struct EdgeMotionRenderSettings: Equatable {
    var mode: MotionBackdropMode
    var speed: Double
    var intensity: Double
    var isPaused: Bool
    var isLight: Bool
    var reduceMotion: Bool

    var shouldAnimate: Bool {
        !isPaused && !reduceMotion
    }
}

final class EdgeMotionMetalView: MTKView {
    private var renderer: EdgeMotionRenderer?
    // These back the nonisolated deinit teardown. The class is @MainActor (MTKView),
    // but deinit is nonisolated and may run off the main thread. Teardown only happens
    // once, with exclusive access at destruction, and the APIs used (CVDisplayLink,
    // NotificationCenter, ProcessInfo.endActivity) are thread-safe — so nonisolated(unsafe)
    // is correct here and avoids the MainActor.assumeIsolated trap (bug #30).
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    private var displayLinkProxy: EdgeMotionDisplayLinkProxy?
    nonisolated(unsafe) private var displayLinkProxyContext: UnsafeMutableRawPointer?
    nonisolated(unsafe) private var appNapActivity: NSObjectProtocol?
    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    private var lastDrawTime: CFTimeInterval = 0

    init(settings: EdgeMotionRenderSettings) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: metalDevice)

        wantsLayer = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1.0)
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        if let metalDevice {
            renderer = EdgeMotionRenderer(
                device: metalDevice,
                pixelFormat: colorPixelFormat,
                settings: settings
            )
            delegate = renderer
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // deinit is nonisolated and may run off the main thread, so do not assert
        // main-actor isolation here (MainActor.assumeIsolated would trap off-main).
        // All of these teardown APIs are thread-safe, so tear down directly.
        if let displayLink {
            if CVDisplayLinkIsRunning(displayLink) {
                CVDisplayLinkStop(displayLink)
            }
            CVDisplayLinkSetOutputCallback(displayLink, nil, nil)
        }
        if let displayLinkProxyContext {
            // Balance the Unmanaged.passRetained from rebuildDisplayLink().
            Unmanaged<EdgeMotionDisplayLinkProxy>.fromOpaque(displayLinkProxyContext).release()
        }
        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
        }
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func apply(settings: EdgeMotionRenderSettings) {
        renderer?.update(settings: settings)
        updateDisplayLinkState()
        draw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureForCurrentWindow()
    }

    func drawFromDisplayLink() {
        guard renderer?.settings.shouldAnimate == true else {
            updateDisplayLinkState()
            return
        }

        guard window?.occlusionState.contains(.visible) == true else {
            updateDisplayLinkState()
            return
        }

        let now = CACurrentMediaTime()
        let targetFPS: Double = (window?.isKeyWindow == true || window?.isMainWindow == true) ? 60 : 30
        guard now - lastDrawTime >= (1.0 / targetFPS) else { return }

        lastDrawTime = now
        draw()
    }

    private func configureForCurrentWindow() {
        removeWindowObservers()

        if let window {
            let center = NotificationCenter.default
            notificationObservers.append(
                center.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.updateDisplayLinkState()
                    }
                }
            )
            notificationObservers.append(
                center.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.rebuildDisplayLink()
                    }
                }
            )
        }

        rebuildDisplayLink()
        draw()
    }

    private func rebuildDisplayLink() {
        stopDisplayLink(releaseLink: true)
        guard window != nil, renderer != nil else { return }

        var nextDisplayLink: CVDisplayLink?
        let displayID = Self.displayID(for: window?.screen)
        let result = CVDisplayLinkCreateWithCGDisplay(displayID, &nextDisplayLink)
        if result != kCVReturnSuccess {
            CVDisplayLinkCreateWithActiveCGDisplays(&nextDisplayLink)
        }

        guard let nextDisplayLink else { return }

        let proxy = EdgeMotionDisplayLinkProxy(view: self)
        displayLinkProxy = proxy
        // The link owns a +1 reference to the proxy so it provably outlives any
        // callback still executing on the CVDisplayLink real-time thread. The
        // matching release happens in stopDisplayLink(releaseLink: true).
        let proxyContext = Unmanaged.passRetained(proxy).toOpaque()
        displayLinkProxyContext = proxyContext
        CVDisplayLinkSetOutputCallback(
            nextDisplayLink,
            edgeMotionDisplayLinkCallback,
            proxyContext
        )
        displayLink = nextDisplayLink
        updateDisplayLinkState()
    }

    private func updateDisplayLinkState() {
        let isVisible = window?.occlusionState.contains(.visible) == true
        let shouldRun = isVisible && (renderer?.settings.shouldAnimate == true)

        if shouldRun {
            startDisplayLink()
        } else {
            stopDisplayLink(releaseLink: false)
        }
    }

    private func startDisplayLink() {
        guard let displayLink else { return }
        guard !CVDisplayLinkIsRunning(displayLink) else { return }

        CVDisplayLinkStart(displayLink)
        if appNapActivity == nil {
            appNapActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated],
                reason: "Edge backdrop"
            )
        }
    }

    private func stopDisplayLink(releaseLink: Bool) {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }

        if let appNapActivity {
            ProcessInfo.processInfo.endActivity(appNapActivity)
            self.appNapActivity = nil
        }

        if releaseLink {
            if let displayLink {
                // Neutralize the callback so no further callbacks can fire after
                // this point. CVDisplayLinkStop does not wait for an in-flight
                // callback, so the retained proxy must outlive any callback still
                // executing on the real-time thread; this clears the context.
                CVDisplayLinkSetOutputCallback(displayLink, nil, nil)
            }
            if let displayLinkProxyContext {
                // Balance the Unmanaged.passRetained from rebuildDisplayLink().
                Unmanaged<EdgeMotionDisplayLinkProxy>.fromOpaque(displayLinkProxyContext).release()
            }
            displayLinkProxyContext = nil
            displayLink = nil
            displayLinkProxy = nil
        }
    }

    private func removeWindowObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private static func displayID(for screen: NSScreen?) -> CGDirectDisplayID {
        guard
            let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return CGMainDisplayID()
        }

        return CGDirectDisplayID(number.uint32Value)
    }
}

final class EdgeMotionDisplayLinkProxy: @unchecked Sendable {
    weak var view: EdgeMotionMetalView?

    init(view: EdgeMotionMetalView) {
        self.view = view
    }

    func tick() {
        DispatchQueue.main.async { [weak view] in
            view?.drawFromDisplayLink()
        }
    }
}

private func edgeMotionDisplayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ now: UnsafePointer<CVTimeStamp>,
    _ outputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let displayLinkContext else { return kCVReturnSuccess }

    let proxy = Unmanaged<EdgeMotionDisplayLinkProxy>
        .fromOpaque(displayLinkContext)
        .takeUnretainedValue()
    proxy.tick()
    return kCVReturnSuccess
}

private final class EdgeMotionRenderer: NSObject, MTKViewDelegate {
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var motionTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval?

    private(set) var settings: EdgeMotionRenderSettings

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, settings: EdgeMotionRenderSettings) {
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.commandQueue = commandQueue
        self.settings = settings

        do {
            let library = try device.makeLibrary(source: edgeMotionShaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "edge_motion_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "edge_motion_fragment")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            return nil
        }

        super.init()
    }

    func update(settings: EdgeMotionRenderSettings) {
        self.settings = settings
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        let now = CACurrentMediaTime()
        let delta = min(0.05, now - (lastFrameTime ?? now))
        lastFrameTime = now

        if settings.shouldAnimate {
            motionTime += delta * settings.speed
        }

        var uniforms = EdgeMotionUniforms(
            resolution: SIMD2<Float>(
                max(Float(view.drawableSize.width), 1),
                max(Float(view.drawableSize.height), 1)
            ),
            time: Float(motionTime),
            intensity: Float(settings.intensity),
            mode: Float(settings.mode.shaderIndex),
            theme: settings.isLight ? 1 : 0,
            reduceMotion: settings.reduceMotion ? 1 : 0,
            pad: 0
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EdgeMotionUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

private struct EdgeMotionUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var intensity: Float
    var mode: Float
    var theme: Float
    var reduceMotion: Float
    var pad: Float
}

private extension MotionBackdropMode {
    var shaderIndex: Int {
        switch self {
        case .aurora: 0
        case .sakura: 1
        case .sparkle: 2
        case .nebula: 3
        }
    }
}

private let edgeMotionShaderSource = #"""
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct Uniforms {
    float2 resolution;
    float time;
    float intensity;
    float mode;
    float theme;
    float reduceMotion;
    float pad;
};

vertex VertexOut edge_motion_vertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
}

float hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

float2 rotate2(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float3 hexColor(float r, float g, float b) {
    return float3(r / 255.0, g / 255.0, b / 255.0);
}

float3 warmColor(int index, bool light) {
    if (light) {
        if (index == 0) return hexColor(255.0, 119.0, 164.0);
        if (index == 1) return hexColor(169.0, 135.0, 255.0);
        if (index == 2) return hexColor(84.0, 178.0, 239.0);
        if (index == 3) return hexColor(70.0, 205.0, 155.0);
        return hexColor(255.0, 172.0, 104.0);
    }

    if (index == 0) return hexColor(255.0, 157.0, 187.0);
    if (index == 1) return hexColor(196.0, 168.0, 255.0);
    if (index == 2) return hexColor(124.0, 215.0, 255.0);
    if (index == 3) return hexColor(139.0, 232.0, 196.0);
    return hexColor(255.0, 197.0, 158.0);
}

float3 coolColor(int index, bool light) {
    if (light) {
        if (index == 0) return hexColor(111.0, 92.0, 255.0);
        if (index == 1) return hexColor(47.0, 182.0, 212.0);
        if (index == 2) return hexColor(163.0, 92.0, 255.0);
        if (index == 3) return hexColor(79.0, 114.0, 255.0);
        return hexColor(31.0, 192.0, 168.0);
    }

    if (index == 0) return hexColor(106.0, 92.0, 255.0);
    if (index == 1) return hexColor(63.0, 208.0, 224.0);
    if (index == 2) return hexColor(176.0, 107.0, 255.0);
    if (index == 3) return hexColor(79.0, 124.0, 255.0);
    return hexColor(43.0, 214.0, 192.0);
}

float3 petalColor(int index, bool light) {
    if (light) {
        if (index == 0) return hexColor(255.0, 122.0, 162.0);
        if (index == 1) return hexColor(201.0, 160.0, 255.0);
        if (index == 2) return hexColor(255.0, 158.0, 196.0);
        return hexColor(155.0, 123.0, 240.0);
    }

    if (index == 0) return hexColor(255.0, 157.0, 187.0);
    if (index == 1) return hexColor(255.0, 208.0, 221.0);
    if (index == 2) return hexColor(255.0, 255.0, 255.0);
    return hexColor(232.0, 216.0, 255.0);
}

float3 sparkleColor(int index, bool light) {
    if (light) {
        if (index == 0) return hexColor(255.0, 122.0, 162.0);
        if (index == 1) return hexColor(91.0, 155.0, 255.0);
        if (index == 2) return hexColor(255.0, 177.0, 60.0);
        return hexColor(176.0, 107.0, 255.0);
    }

    if (index == 0) return hexColor(255.0, 227.0, 241.0);
    if (index == 1) return hexColor(216.0, 236.0, 255.0);
    if (index == 2) return hexColor(255.0, 244.0, 214.0);
    return hexColor(255.0, 255.0, 255.0);
}

float3 baseGradient(float2 uv, bool light) {
    // Light-mode bands are deliberately muted (~20% darker than pure pastel) so the
    // animated motion wisps stay visible instead of washing out on a near-white base.
    float3 bandA = light ? hexColor(206.0, 180.0, 192.0) : hexColor(29.0, 22.0, 64.0);
    float3 bandB = light ? hexColor(176.0, 190.0, 212.0) : hexColor(36.0, 27.0, 70.0);
    float3 bandC = light ? hexColor(192.0, 180.0, 212.0) : hexColor(44.0, 29.0, 72.0);

    float3 leftMid = mix(bandA, bandB, smoothstep(0.0, 0.58, uv.x));
    return mix(leftMid, bandC, smoothstep(0.42, 1.0, uv.x));
}

float radial(float2 uv, float2 center, float radius) {
    float distanceToCenter = distance(uv, center) / radius;
    return pow(saturate(1.0 - distanceToCenter), 2.25);
}

float auroraField(float2 uv, float2 center, float radius) {
    float d = distance(uv, center) / radius;
    return smoothstep(1.0, 0.0, d) * smoothstep(1.2, 0.0, d);
}

float3 drawAurora(float2 uv, Uniforms u, bool light, int mode) {
    float t = u.time;
    float intensity = u.intensity;
    float3 color = float3(0.0);

    float2 centers[5] = {
        float2(0.16, 0.30),
        float2(0.40, 0.76),
        float2(0.63, 0.26),
        float2(0.85, 0.70),
        float2(0.50, 0.50)
    };
    float2 freq[5] = {
        float2(0.055, 0.075),
        float2(0.048, 0.066),
        float2(0.066, 0.050),
        float2(0.052, 0.078),
        float2(0.040, 0.060)
    };
    float2 amp[5] = {
        float2(0.050, 0.110),
        float2(0.060, 0.090),
        float2(0.050, 0.100),
        float2(0.060, 0.080),
        float2(0.070, 0.070)
    };
    float radius[5] = { 0.44, 0.48, 0.42, 0.50, 0.38 };
    float phase[5] = { 0.2, 1.1, 2.3, 3.0, 4.2 };

    for (int i = 0; i < 5; i++) {
        float2 center = centers[i] + float2(
            sin(t * freq[i].x * 6.2831853 + phase[i]) * amp[i].x,
            cos(t * freq[i].y * 6.2831853 + phase[i]) * amp[i].y
        );
        float r = radius[i] * (0.92 + 0.08 * sin(t * 0.7 + phase[i]));
        float field = auroraField(uv, center, r);
        float3 blob = mode == 3 ? coolColor(i, light) : warmColor(i, light);
        float alpha = (light ? 0.78 : 0.40) * intensity;
        color += blob * field * alpha;
    }

    return color;
}

float3 drawSakura(float2 pixel, Uniforms u, bool light) {
    float3 color = float3(0.0);
    float t = u.time;

    for (int i = 0; i < 70; i++) {
        float fi = float(i);
        float h0 = hash11(fi * 17.13 + 1.0);
        float h1 = hash11(fi * 29.71 + 4.0);
        float h2 = hash11(fi * 41.91 + 7.0);
        float h3 = hash11(fi * 13.41 + 11.0);
        float h4 = hash11(fi * 73.83 + 3.0);

        float size = 9.0 + h2 * 16.0;
        float fall = 14.0 + h3 * 28.0;
        float drift = 5.0 + h4 * 15.0;
        float cycle = fract(h1 + t * fall / 720.0);
        float2 pos = float2(h0 * u.resolution.x, cycle * (u.resolution.y + 48.0) - 24.0);
        pos.x += t * drift + sin(t * 0.6 + h1 * 6.2831853) * (12.0 + h4 * 26.0);
        pos.x = fmod(pos.x + 24.0, u.resolution.x + 48.0) - 24.0;

        float angle = h3 * 6.2831853 + t * ((h4 - 0.5) * 1.3);
        float2 q = rotate2((pixel - pos) / size, angle);
        float body = exp(-dot(q * float2(1.24, 0.68), q * float2(1.24, 0.68)) * 2.7);
        body *= smoothstep(1.25, 0.15, length(q * float2(0.78, 1.22)));

        float alpha = (0.32 + h1 * 0.42) * u.intensity;
        color += petalColor(int(floor(h4 * 4.0)), light) * body * alpha;
    }

    return color;
}

float3 drawSparkle(float2 pixel, Uniforms u, bool light) {
    float3 color = float3(0.0);
    float t = u.time;

    for (int i = 0; i < 48; i++) {
        float fi = float(i);
        float h0 = hash11(fi * 18.31 + 5.0);
        float h1 = hash11(fi * 44.09 + 9.0);
        float h2 = hash11(fi * 12.73 + 2.0);
        float h3 = hash11(fi * 65.47 + 6.0);

        float radius = 2.0 + h2 * 7.0;
        float rise = 7.0 + h3 * 22.0;
        float cycle = fract(h1 + t * rise / 720.0);
        float2 pos = float2(h0 * u.resolution.x, u.resolution.y + 24.0 - cycle * (u.resolution.y + 48.0));
        float d = distance(pixel, pos);
        float glow = smoothstep(radius * 5.8, 0.0, d);
        float twinkle = 0.5 + 0.5 * sin(t * (0.6 + h2 * 1.6) + h3 * 6.2831853);
        float cross = max(
            smoothstep(radius * 8.0, 0.0, abs(pixel.x - pos.x)) * smoothstep(radius * 1.1, 0.0, abs(pixel.y - pos.y)),
            smoothstep(radius * 8.0, 0.0, abs(pixel.y - pos.y)) * smoothstep(radius * 1.1, 0.0, abs(pixel.x - pos.x))
        );

        float alpha = (0.24 + h1 * 0.46) * twinkle * u.intensity;
        color += sparkleColor(int(floor(h3 * 4.0)), light) * (glow + cross * 0.45) * alpha;
    }

    return color;
}

float3 drawNebula(float2 pixel, Uniforms u, bool light) {
    float3 color = float3(0.0);
    float t = u.time;

    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float h0 = hash11(fi * 23.9 + 2.0);
        float h1 = hash11(fi * 81.2 + 8.0);
        float h2 = hash11(fi * 55.7 + 1.0);
        float moteRadius = 34.0 + h2 * 78.0;
        float2 pos = float2(
            fmod(h0 * u.resolution.x + t * (4.0 + h1 * 11.0), u.resolution.x + moteRadius * 2.0) - moteRadius,
            h1 * u.resolution.y
        );
        float glow = smoothstep(moteRadius, 0.0, distance(pixel, pos));
        color += coolColor(i % 5, light) * glow * (0.05 + h0 * 0.06) * u.intensity;
    }

    for (int i = 0; i < 64; i++) {
        float fi = float(i);
        float h0 = hash11(fi * 37.2 + 4.0);
        float h1 = hash11(fi * 91.7 + 6.0);
        float h2 = hash11(fi * 14.6 + 2.0);
        float2 pos = float2(h0 * u.resolution.x, h1 * u.resolution.y);
        float radius = 0.7 + h2 * 1.9;
        float star = smoothstep(radius * 2.8, 0.0, distance(pixel, pos));
        float twinkle = 0.4 + 0.6 * sin(t * (0.4 + h2 * 1.5) + h1 * 6.2831853);
        float3 starColor = light ? hexColor(157.0, 123.0, 224.0) : float3(1.0);
        color += starColor * star * twinkle * (0.24 + h2 * 0.52) * u.intensity;
    }

    return color;
}

fragment half4 edge_motion_fragment(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    bool light = u.theme > 0.5;
    int mode = u.reduceMotion > 0.5 ? 0 : int(u.mode + 0.5);
    float2 uv = clamp(in.uv, 0.0, 1.0);
    float2 pixel = uv * u.resolution;

    float3 color = baseGradient(uv, light);

    float3 aurora = drawAurora(uv, u, light, mode);
    if (light) {
        color = mix(color, color + aurora, 0.76);
    } else {
        color += aurora;
    }

    if (mode == 1) {
        color += drawSakura(pixel, u, light) * (light ? 1.08 : 0.94);
    } else if (mode == 2) {
        color += drawSparkle(pixel, u, light) * (light ? 0.90 : 0.98);
    } else if (mode == 3) {
        color += drawNebula(pixel, u, light) * (light ? 0.98 : 1.06);
    }

    float3 celPink = hexColor(255.0, 157.0, 187.0) * radial(uv, float2(0.11, -0.10), 0.56) * (light ? 0.22 : 0.18);
    float3 celSky = hexColor(124.0, 215.0, 255.0) * radial(uv, float2(0.93, 1.12), 0.56) * (light ? 0.20 : 0.16);
    float3 celLav = hexColor(196.0, 168.0, 255.0) * radial(uv, float2(0.50, 0.50), 0.70) * (light ? 0.15 : 0.10);
    color += (celPink + celSky + celLav) * u.intensity;

    float vignette = smoothstep(0.52, 1.05, distance(uv, float2(0.5)));
    color = light ? mix(color, color * 0.94, vignette * 0.18) : mix(color, color * 0.58, vignette * 0.52);

    return half4(float4(saturate(color), 1.0));
}
"""#
