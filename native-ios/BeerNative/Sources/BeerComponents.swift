import SwiftUI
import UIKit

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
        .padding(.top, 12)
        .padding(.bottom, 16)
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
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { current = index }
        } label: {
            Text(title)
                .font(.system(size: Theme.Font.step, weight: index == current ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 5)
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
                Text(title)
                    .font(.system(size: Theme.Font.btn, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(Theme.primaryGradient)
            .foregroundStyle(Theme.btnPrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
        }
        .disabled(disabled || busy)
        .opacity(disabled || busy ? 0.45 : 1)
        .padding(.top, 10)
    }
}

struct BeerSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.Font.btn, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .padding(.horizontal, 16)
                .background(Theme.card)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.btn))
        }
        .padding(.top, 10)
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
                .font(.system(size: Theme.Font.ghost, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.clear)
                .foregroundStyle(Theme.text)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.btn).stroke(Theme.border))
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
                .font(.system(size: Theme.Font.field))
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
            .font(.system(size: Theme.Font.lead))
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
    @State private var lastHapticRating: Double = 0

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
                            let snapped = (raw / step).rounded() * step
                            if snapped != lastHapticRating {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                lastHapticRating = snapped
                            }
                            rating = snapped
                        }
                )
                .onAppear { lastHapticRating = rating }
            }
            .frame(height: 28)
            Text("\(BeerFormatters.ratingLabel(rating))/5")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.star)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Custom tags

struct CustomTagInput: View {
    let placeholder: String
    @Binding var input: String
    @Binding var selected: Set<String>
    let maxCount: Int
    var onRegister: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Theme.text)
                .onSubmit { add() }
            Button("+", action: add)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(input.trimmingCharacters(in: .whitespaces).count < 2)
        }
    }

    private func add() {
        let tag = input.trimmingCharacters(in: .whitespaces)
        guard tag.count >= 2, selected.count < maxCount, !selected.contains(tag) else { return }
        onRegister?(tag)
        selected.insert(tag)
        input = ""
    }
}

struct CustomTagChips: View {
    @Binding var selected: Set<String>
    let customOnly: Set<String>

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(customOnly).sorted(), id: \.self) { tag in
                Button {
                    selected.remove(tag)
                } label: {
                    Text("\(tag) ×")
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.2))
                        .foregroundStyle(Theme.accent)
                        .overlay(Capsule().stroke(Theme.accent))
                        .clipShape(Capsule())
                }
            }
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
                .font(.system(size: Theme.Font.tagTitle))
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    let on = selected.contains(tag)
                    Button {
                        if on { selected.remove(tag) }
                        else if selected.count < maxCount { selected.insert(tag) }
                    } label: {
                        Text(tag)
                            .font(.system(size: Theme.Font.tag))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(on ? Theme.accent.opacity(0.2) : Theme.card)
                            .foregroundStyle(on ? Theme.accent : Theme.text)
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
        .beerShadow()
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

// MARK: - Filter chips

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent.opacity(0.22) : Theme.card)
                .foregroundStyle(selected ? Theme.accent : Theme.muted)
                .overlay(Capsule().stroke(selected ? Theme.accent.opacity(0.55) : Theme.border))
                .clipShape(Capsule())
        }
    }
}

struct BeerEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(icon).font(.system(size: 36))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }
}

struct InviteHelpBar: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            (
                Text("Conseil").fontWeight(.semibold).foregroundStyle(Theme.accent)
                + Text(" — garde Beer Log installé sur ton écran d'accueil et évite de vider ses données dans les réglages du téléphone : c'est ce qui maintient ta connexion.")
                    .foregroundStyle(Theme.text)
            )
            .font(.system(size: 12.8))
            .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Text("×")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(hex: 0xc9a227).opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xc9a227).opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct OfflineBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Text("Hors ligne")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.accent.opacity(0.12))
        .overlay(Capsule().stroke(Theme.accent.opacity(0.3)))
        .clipShape(Capsule())
    }
}