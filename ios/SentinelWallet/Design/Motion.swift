import SwiftUI

/// One place for every animation, so the whole app moves at the same tempo.
enum Motion {
    /// The house spring: identical feel to the web build's cubic-bezier(.22,.9,.24,1).
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.1)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.68)
    static let slow = Animation.spring(response: 0.7, dampingFraction: 0.9)
    static let linear = Animation.linear(duration: 0.25)

    /// A scan sweep: fast out, gentle settle, repeated while work is happening.
    static let sweep = Animation.easeInOut(duration: 1.6)
    static let pulse = Animation.easeInOut(duration: 1.1)
    static let shimmer = Animation.linear(duration: 2.2)

    static func stagger(_ index: Int, step: Double = 0.05) -> Animation {
        smooth.delay(Double(index) * step)
    }
}

/// Scales and dims on press, with a haptic tick. Used by every tappable surface.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.965
    var dimming: Double = 0.9
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? dimming : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in
                haptic && pressed
            }
    }
}

extension View {
    /// Cross-fades and lifts content in, staggered by list position.
    func appearIn(_ index: Int = 0) -> some View {
        modifier(AppearIn(index: index))
    }
}

private struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(Motion.stagger(index)) { shown = true }
            }
    }
}

/// A slow, looping sheen used while data is being fetched.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(colors: [.clear, Color.white.opacity(0.16), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .rotationEffect(.degrees(18))
                    .offset(x: phase * 320)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(Motion.shimmer.repeatForever(autoreverses: false)) { phase = 1.4 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}
