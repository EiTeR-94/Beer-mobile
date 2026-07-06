import SwiftUI

// MARK: - Header

struct BeerHeader: View {
    let username: String?
    let onHistory: () -> Void
    let onLogout: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beer Log")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("scan · photo · note")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let username {
                    Text(username)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.card)
                        .overlay(Capsule().stroke(Theme.border))
                        .clipShape(Capsule())
                }
                BeerGhostButton("Historique", action: onHistory)
                BeerGhostButton("Déconnexion", action: onLogout)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.bg)
    }
}

// MARK: - Steps

struct BeerStepNav: View {
    @Binding var step: Int

    var body: some View {
        HStack(spacing: 8) {
            BeerStepButton(title: "1 Bière", index: 1, current: $step)
            BeerStepButton(title: "2 Photo", index: 2, current: $step)
            BeerStepButton(title: "3 Note", index: 3, current: $step)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Theme.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

struct BeerStepButton: View {
    let title: String
    let index: Int
    @Binding var current: Int

    var body: some View {
        Button { current = index } label: {
            Text(title)
                .font(.system(size: 12, weight: index == current ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(index == current ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Theme.card))
                .foregroundStyle(index == current ? Theme.btnPrimaryText : Theme.muted)
                .overlay(Capsule().stroke(index == current ? Color.clear : Theme.border))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Buttons & fields

struct BeerPrimaryButton: View {
    let title: String
    var disabled = false
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(Theme.btnPrimaryText) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.primaryGradient)
            .foregroundStyle(Theme.btnPrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(disabled || busy)
        .opacity(disabled || busy ? 0.55 : 1)
    }
}

struct BeerSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.card)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct BeerGhostButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.clear)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        }
    }
}

struct BeerField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(Theme.text)
        }
    }
}

struct BeerLead: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Beer preview card

struct BeerPreviewCard: View {
    let product: BeerProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(product.beerName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            if !product.summary.isEmpty {
                Text(product.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .beerCard()
    }

    private var metaLine: String {
        [product.brewery, product.displayStyle, product.abv.map { String(format: "%.1f%%", $0) }]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
    }
}

// MARK: - Scan overlay

struct ScanViewfinderOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let fw = geo.size.width * 0.82
            let fh = geo.size.height * 0.28
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let hole = CGRect(x: cx - fw / 2, y: cy - fh / 2, width: fw, height: fh)

            ZStack {
                Color.black.opacity(0.58)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .frame(width: fw, height: fh)
                                    .blendMode(.destinationOut)
                            )
                    )

                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.accent, lineWidth: 2)
                    .frame(width: fw, height: fh)
                    .position(x: cx, y: cy)

                ScanCorner().position(x: hole.minX, y: hole.minY)
                ScanCorner().rotationEffect(.degrees(90)).position(x: hole.maxX, y: hole.minY)
                ScanCorner().rotationEffect(.degrees(-90)).position(x: hole.minX, y: hole.maxY)
                ScanCorner().rotationEffect(.degrees(180)).position(x: hole.maxX, y: hole.maxY)

                ScanLine()
                    .frame(width: fw * 0.88, height: 2)
                    .position(x: cx, y: hole.minY + fh * 0.15)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ScanCorner: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 14))
            p.addLine(to: .zero)
            p.addLine(to: CGPoint(x: 14, y: 0))
        }
        .stroke(Theme.accent, lineWidth: 2)
        .frame(width: 14, height: 14)
    }
}

private struct ScanLine: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Theme.accent, .clear], startPoint: .leading, endPoint: .trailing))
            .offset(y: phase)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    phase = 40
                }
            }
    }
}

// MARK: - Untappd rating slider

struct UntappdRatingSlider: View {
    @Binding var rating: Double

    private let minR = 0.25
    private let maxR = 5.0
    private let step = 0.25

    var body: some View {
        HStack(spacing: 8) {
            Text("NOTE")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            GeometryReader { geo in
                let pct = (rating - minR) / (maxR - minR)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x64748b)).frame(height: 2)
                    Capsule().fill(Theme.star).frame(width: geo.size.width * pct, height: 2)
                    ForEach(Array(stride(from: minR, through: maxR, by: step)), id: \.self) { tick in
                        let t = (tick - minR) / (maxR - minR)
                        Rectangle()
                            .fill(Theme.star)
                            .frame(width: 1, height: 5)
                            .position(x: geo.size.width * t, y: geo.size.height / 2)
                    }
                    Circle()
                        .fill(Theme.star)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(hex: 0x0f172a), lineWidth: 2))
                        .position(x: geo.size.width * pct, y: geo.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let raw = minR + (maxR - minR) * max(0, min(1, v.location.x / geo.size.width))
                            rating = (raw / step).rounded() * step
                        }
                )
            }
            .frame(height: 28)
            Text(String(format: "%.2f", rating))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.star)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Flavor tags

struct FlavorTagGrid: View {
    let title: String
    let tags: [String]
    @Binding var selected: Set<String>
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    let on = selected.contains(tag)
                    Button {
                        if on { selected.remove(tag) }
                        else if selected.count < maxCount { selected.insert(tag) }
                    } label: {
                        Text(tag)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(on ? Theme.accent.opacity(0.25) : Theme.bg)
                            .foregroundStyle(on ? Theme.accent : Theme.muted)
                            .overlay(Capsule().stroke(on ? Theme.accent : Theme.border))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var positions: [CGPoint] = []

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxW && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxW, height: y + rowH), positions)
    }
}

// MARK: - History card

struct HistoryCardView: View {
    let item: CheckinItem
    var photoBase: URL = ServerSettings.apiBase

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            photoView
            VStack(alignment: .leading, spacing: 4) {
                Text(item.beerName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 4) {
                    Text("★★★★★")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.starOff)
                        .overlay(alignment: .leading) {
                            Text("★★★★★")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.star)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: starFill)
                                }
                        }
                    Text(String(format: "%.2f", item.rating))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                if let brewery = item.brewery, !brewery.isEmpty {
                    Text(brewery)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                if let style = item.style, !style.isEmpty {
                    Text(style)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                if let comment = item.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 13))
                        .italic()
                        .foregroundStyle(Theme.text)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bg.opacity(0.55))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.accent).frame(width: 3)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var photoView: some View {
        if let url = resolvedPhotoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    photoPlaceholder
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4]))
            .background(Theme.bg)
            .frame(width: 88, height: 88)
            .overlay(Text("🍺").font(.title2))
    }

    private var resolvedPhotoURL: URL? {
        ServerSettings.resolveAssetURL(item.photoURL, base: photoBase)
    }

    private var starFill: CGFloat {
        CGFloat(item.rating / 5.0) * 55
    }
}