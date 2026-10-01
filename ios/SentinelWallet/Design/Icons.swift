import SwiftUI

/// Icons drawn as paths rather than borrowed from SF Symbols, so the app has its own hand:
/// consistent 1.8 pt strokes, round caps, and a house grid of 24×24.
enum Icon: CaseIterable {
    case vault, shield, scan, wallet, activity, layers, lookup, alert, check, copy, eyeOff,
         eye, chevron, plus, trash, history, globe, lock, key, sparkle, refresh, info, close,
         arrowDown, arrowUp, dots, filter, share, qr

    var path: Path {
        var path = Path()
        switch self {
        case .vault:
            path.addRoundedRect(in: CGRect(x: 3, y: 3, width: 18, height: 18), cornerSize: CGSize(width: 5, height: 5))
            path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            path.move(to: CGPoint(x: 12, y: 6)); path.addLine(to: CGPoint(x: 12, y: 9))
        case .shield:
            path.move(to: CGPoint(x: 12, y: 3))
            path.addLine(to: CGPoint(x: 19, y: 6))
            path.addLine(to: CGPoint(x: 19, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 21),
                          control1: CGPoint(x: 19, y: 17), control2: CGPoint(x: 15.5, y: 20))
            path.addCurve(to: CGPoint(x: 5, y: 12),
                          control1: CGPoint(x: 8.5, y: 20), control2: CGPoint(x: 5, y: 17))
            path.addLine(to: CGPoint(x: 5, y: 6))
            path.closeSubpath()
        case .scan:
            path.move(to: CGPoint(x: 3, y: 8)); path.addLine(to: CGPoint(x: 3, y: 5))
            path.addLine(to: CGPoint(x: 8, y: 5))
            path.move(to: CGPoint(x: 16, y: 3)); path.addLine(to: CGPoint(x: 21, y: 3))
            path.addLine(to: CGPoint(x: 21, y: 8))
            path.move(to: CGPoint(x: 21, y: 16)); path.addLine(to: CGPoint(x: 21, y: 21))
            path.addLine(to: CGPoint(x: 16, y: 21))
            path.move(to: CGPoint(x: 8, y: 21)); path.addLine(to: CGPoint(x: 3, y: 21))
            path.addLine(to: CGPoint(x: 3, y: 16))
            path.move(to: CGPoint(x: 3, y: 12)); path.addLine(to: CGPoint(x: 21, y: 12))
        case .wallet:
            path.addRoundedRect(in: CGRect(x: 3, y: 6, width: 18, height: 13), cornerSize: CGSize(width: 4, height: 4))
            path.move(to: CGPoint(x: 3, y: 10)); path.addLine(to: CGPoint(x: 16, y: 10))
            path.addEllipse(in: CGRect(x: 15, y: 12, width: 3.5, height: 3.5))
        case .activity:
            path.move(to: CGPoint(x: 3, y: 13)); path.addLine(to: CGPoint(x: 7, y: 13))
            path.addLine(to: CGPoint(x: 9.5, y: 7)); path.addLine(to: CGPoint(x: 13, y: 18))
            path.addLine(to: CGPoint(x: 15.5, y: 12)); path.addLine(to: CGPoint(x: 21, y: 12))
        case .layers:
            path.move(to: CGPoint(x: 12, y: 3)); path.addLine(to: CGPoint(x: 21, y: 8))
            path.addLine(to: CGPoint(x: 12, y: 13)); path.addLine(to: CGPoint(x: 3, y: 8)); path.closeSubpath()
            path.move(to: CGPoint(x: 4.5, y: 12.5)); path.addLine(to: CGPoint(x: 12, y: 16.5))
            path.addLine(to: CGPoint(x: 19.5, y: 12.5))
            path.move(to: CGPoint(x: 6, y: 16.5)); path.addLine(to: CGPoint(x: 12, y: 19.8))
            path.addLine(to: CGPoint(x: 18, y: 16.5))
        case .lookup:
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 11, height: 11))
            path.move(to: CGPoint(x: 13.5, y: 13.5)); path.addLine(to: CGPoint(x: 20, y: 20))
        case .alert:
            path.move(to: CGPoint(x: 12, y: 3.5)); path.addLine(to: CGPoint(x: 21, y: 19.5))
            path.addLine(to: CGPoint(x: 3, y: 19.5)); path.closeSubpath()
            path.move(to: CGPoint(x: 12, y: 9)); path.addLine(to: CGPoint(x: 12, y: 14))
            path.move(to: CGPoint(x: 12, y: 16.6)); path.addLine(to: CGPoint(x: 12, y: 16.7))
        case .check:
            path.move(to: CGPoint(x: 4.5, y: 12.5)); path.addLine(to: CGPoint(x: 9.5, y: 17.5))
            path.addLine(to: CGPoint(x: 19.5, y: 6.5))
        case .copy:
            path.addRoundedRect(in: CGRect(x: 8, y: 8, width: 12, height: 12), cornerSize: CGSize(width: 3.5, height: 3.5))
            path.move(to: CGPoint(x: 16, y: 5)); path.addLine(to: CGPoint(x: 5, y: 5))
            path.addLine(to: CGPoint(x: 5, y: 16))
        case .eye:
            path.move(to: CGPoint(x: 2.5, y: 12))
            path.addQuadCurve(to: CGPoint(x: 21.5, y: 12), control: CGPoint(x: 12, y: 4))
            path.addQuadCurve(to: CGPoint(x: 2.5, y: 12), control: CGPoint(x: 12, y: 20))
            path.addEllipse(in: CGRect(x: 9.5, y: 9.5, width: 5, height: 5))
        case .eyeOff:
            path.move(to: CGPoint(x: 3, y: 12))
            path.addQuadCurve(to: CGPoint(x: 21, y: 12), control: CGPoint(x: 12, y: 4.5))
            path.move(to: CGPoint(x: 5, y: 19)); path.addLine(to: CGPoint(x: 19, y: 5))
        case .chevron:
            path.move(to: CGPoint(x: 9, y: 5)); path.addLine(to: CGPoint(x: 16, y: 12))
            path.addLine(to: CGPoint(x: 9, y: 19))
        case .plus:
            path.move(to: CGPoint(x: 12, y: 5)); path.addLine(to: CGPoint(x: 12, y: 19))
            path.move(to: CGPoint(x: 5, y: 12)); path.addLine(to: CGPoint(x: 19, y: 12))
        case .trash:
            path.move(to: CGPoint(x: 4.5, y: 7)); path.addLine(to: CGPoint(x: 19.5, y: 7))
            path.move(to: CGPoint(x: 9.5, y: 7)); path.addLine(to: CGPoint(x: 9.5, y: 4.5))
            path.addLine(to: CGPoint(x: 14.5, y: 4.5)); path.addLine(to: CGPoint(x: 14.5, y: 7))
            path.move(to: CGPoint(x: 6.5, y: 7)); path.addLine(to: CGPoint(x: 7.6, y: 19.5))
            path.addLine(to: CGPoint(x: 16.4, y: 19.5)); path.addLine(to: CGPoint(x: 17.5, y: 7))
            path.move(to: CGPoint(x: 10.5, y: 10.5)); path.addLine(to: CGPoint(x: 10.9, y: 16.5))
            path.move(to: CGPoint(x: 13.5, y: 10.5)); path.addLine(to: CGPoint(x: 13.1, y: 16.5))
        case .history:
            path.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            path.move(to: CGPoint(x: 12, y: 7.5)); path.addLine(to: CGPoint(x: 12, y: 12.5))
            path.addLine(to: CGPoint(x: 15.5, y: 14.5))
        case .globe:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 3, y: 12)); path.addLine(to: CGPoint(x: 21, y: 12))
            path.move(to: CGPoint(x: 12, y: 3))
            path.addQuadCurve(to: CGPoint(x: 12, y: 21), control: CGPoint(x: 5, y: 12))
            path.addQuadCurve(to: CGPoint(x: 12, y: 3), control: CGPoint(x: 19, y: 12))
        case .lock:
            path.addRoundedRect(in: CGRect(x: 5, y: 10.5, width: 14, height: 10), cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 8, y: 10.5)); path.addLine(to: CGPoint(x: 8, y: 8))
            path.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 8, y: 3.5), control2: CGPoint(x: 16, y: 3.5))
            path.addLine(to: CGPoint(x: 16, y: 10.5))
            path.move(to: CGPoint(x: 12, y: 14)); path.addLine(to: CGPoint(x: 12, y: 16.5))
        case .key:
            path.addEllipse(in: CGRect(x: 4, y: 9, width: 7, height: 7))
            path.move(to: CGPoint(x: 10.5, y: 12.5)); path.addLine(to: CGPoint(x: 20, y: 12.5))
            path.move(to: CGPoint(x: 17, y: 12.5)); path.addLine(to: CGPoint(x: 17, y: 16))
            path.move(to: CGPoint(x: 20, y: 12.5)); path.addLine(to: CGPoint(x: 20, y: 15))
        case .sparkle:
            path.move(to: CGPoint(x: 12, y: 3)); path.addLine(to: CGPoint(x: 13.6, y: 9.4))
            path.addLine(to: CGPoint(x: 20, y: 11)); path.addLine(to: CGPoint(x: 13.6, y: 12.6))
            path.addLine(to: CGPoint(x: 12, y: 19)); path.addLine(to: CGPoint(x: 10.4, y: 12.6))
            path.addLine(to: CGPoint(x: 4, y: 11)); path.addLine(to: CGPoint(x: 10.4, y: 9.4))
            path.closeSubpath()
        case .refresh:
            path.addArc(center: CGPoint(x: 12, y: 12), radius: 8,
                        startAngle: .degrees(-40), endAngle: .degrees(220), clockwise: false)
            path.move(to: CGPoint(x: 17.5, y: 2.5)); path.addLine(to: CGPoint(x: 18.4, y: 8.2))
            path.addLine(to: CGPoint(x: 13, y: 7.2))
        case .info:
            path.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            path.move(to: CGPoint(x: 12, y: 10.5)); path.addLine(to: CGPoint(x: 12, y: 16.5))
            path.move(to: CGPoint(x: 12, y: 7.6)); path.addLine(to: CGPoint(x: 12, y: 7.7))
        case .close:
            path.move(to: CGPoint(x: 6, y: 6)); path.addLine(to: CGPoint(x: 18, y: 18))
            path.move(to: CGPoint(x: 18, y: 6)); path.addLine(to: CGPoint(x: 6, y: 18))
        case .arrowDown:
            path.move(to: CGPoint(x: 12, y: 4.5)); path.addLine(to: CGPoint(x: 12, y: 19))
            path.move(to: CGPoint(x: 6.5, y: 13.5)); path.addLine(to: CGPoint(x: 12, y: 19))
            path.addLine(to: CGPoint(x: 17.5, y: 13.5))
        case .arrowUp:
            path.move(to: CGPoint(x: 12, y: 19.5)); path.addLine(to: CGPoint(x: 12, y: 5))
            path.move(to: CGPoint(x: 6.5, y: 10.5)); path.addLine(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 17.5, y: 10.5))
        case .dots:
            path.addEllipse(in: CGRect(x: 4.5, y: 10.5, width: 3, height: 3))
            path.addEllipse(in: CGRect(x: 10.5, y: 10.5, width: 3, height: 3))
            path.addEllipse(in: CGRect(x: 16.5, y: 10.5, width: 3, height: 3))
        case .filter:
            path.move(to: CGPoint(x: 4, y: 6)); path.addLine(to: CGPoint(x: 20, y: 6))
            path.move(to: CGPoint(x: 7, y: 12)); path.addLine(to: CGPoint(x: 17, y: 12))
            path.move(to: CGPoint(x: 10, y: 18)); path.addLine(to: CGPoint(x: 14, y: 18))
        case .share:
            path.move(to: CGPoint(x: 12, y: 3.5)); path.addLine(to: CGPoint(x: 12, y: 14.5))
            path.move(to: CGPoint(x: 8, y: 7.5)); path.addLine(to: CGPoint(x: 12, y: 3.5))
            path.addLine(to: CGPoint(x: 16, y: 7.5))
            path.move(to: CGPoint(x: 5.5, y: 12.5)); path.addLine(to: CGPoint(x: 5.5, y: 19.5))
            path.addLine(to: CGPoint(x: 18.5, y: 19.5)); path.addLine(to: CGPoint(x: 18.5, y: 12.5))
        case .qr:
            path.addRect(CGRect(x: 3.5, y: 3.5, width: 7, height: 7))
            path.addRect(CGRect(x: 13.5, y: 3.5, width: 7, height: 7))
            path.addRect(CGRect(x: 3.5, y: 13.5, width: 7, height: 7))
            path.move(to: CGPoint(x: 13.5, y: 13.5)); path.addLine(to: CGPoint(x: 20.5, y: 13.5))
            path.move(to: CGPoint(x: 17, y: 13.5)); path.addLine(to: CGPoint(x: 17, y: 20.5))
            path.move(to: CGPoint(x: 13.5, y: 17)); path.addLine(to: CGPoint(x: 20.5, y: 17))
        }
        return path
    }
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 22
    var weight: CGFloat = 1.8
    var color: Color = Theme.text

    var body: some View {
        IconShape(icon: icon)
            .stroke(color, style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct IconShape: Shape {
    let icon: Icon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return icon.path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
