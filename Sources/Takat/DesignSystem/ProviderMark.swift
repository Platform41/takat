import SwiftUI

struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            switch provider {
            case .gemini:
                context.fill(geminiPath(in: rect), with: .foreground)
            case .claude:
                context.fill(claudePath(in: rect), with: .foreground)
            case .codex:
                let stroke = StrokeStyle(
                    lineWidth: min(canvasSize.width, canvasSize.height) * 0.16,
                    lineCap: .round,
                    lineJoin: .round
                )
                context.stroke(codexPath(in: rect), with: .foreground, style: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func geminiPath(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let s = min(rect.width, rect.height)
        let outer = s * 0.5
        let inner = s * 0.16

        func point(degrees: CGFloat, radius: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        }

        var path = Path()
        path.move(to: point(degrees: 0, radius: outer))
        path.addQuadCurve(to: point(degrees: 90, radius: outer), control: point(degrees: 45, radius: inner))
        path.addQuadCurve(to: point(degrees: 180, radius: outer), control: point(degrees: 135, radius: inner))
        path.addQuadCurve(to: point(degrees: 270, radius: outer), control: point(degrees: 225, radius: inner))
        path.addQuadCurve(to: point(degrees: 360, radius: outer), control: point(degrees: 315, radius: inner))
        path.closeSubpath()
        return path
    }

    private func claudePath(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let s = min(rect.width, rect.height)
        let rays = 12
        let halfWidth: CGFloat = 0.12

        var path = Path()
        for i in 0..<rays {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(rays)
            let radius = (i % 2 == 0) ? s * 0.5 : s * 0.36
            let p1 = CGPoint(x: c.x + radius * cos(angle - halfWidth), y: c.y + radius * sin(angle - halfWidth))
            let p2 = CGPoint(x: c.x + radius * cos(angle + halfWidth), y: c.y + radius * sin(angle + halfWidth))
            let tip = CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))

            path.move(to: c)
            path.addLine(to: p1)
            path.addQuadCurve(to: p2, control: tip)
            path.closeSubpath()
        }
        return path
    }

    private func codexPath(in rect: CGRect) -> Path {
        var path = Path()

        let tip = CGPoint(x: rect.width * 0.70, y: rect.midY)
        let topLeft = CGPoint(x: rect.width * 0.30, y: rect.height * 0.24)
        let bottomLeft = CGPoint(x: rect.width * 0.30, y: rect.height * 0.76)
        path.move(to: topLeft)
        path.addLine(to: tip)
        path.addLine(to: bottomLeft)

        let barStart = CGPoint(x: rect.width * 0.55, y: rect.height * 0.82)
        let barEnd = CGPoint(x: rect.width * 0.88, y: rect.height * 0.82)
        path.move(to: barStart)
        path.addLine(to: barEnd)

        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(ProviderID.allCases, id: \.self) { provider in
            ProviderMark(provider: provider, size: 24)
                .foregroundStyle(provider.accentColor)
        }
    }
    .padding()
}
