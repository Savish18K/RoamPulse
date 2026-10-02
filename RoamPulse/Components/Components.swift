import SwiftUI

// MARK: - Card

/// Rounded card background used for most boxes in the prototype.
struct CardModifier: ViewModifier {
    var padding: CGFloat
    var fill: Color
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Text field / picker box used in forms and sheets.
struct FieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = Theme.card, cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(CardModifier(padding: padding, fill: fill, cornerRadius: cornerRadius))
    }

    func fieldStyle() -> some View {
        modifier(FieldModifier())
    }
}

/// Small grey uppercase heading, e.g. "SETTINGS".
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label + field pair used in the create/add sheets.
struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            content.fieldStyle()
        }
    }
}

/// Icon + title + value tile (Trip detail, Landmark detail).
struct StatTile: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .card(padding: 14, cornerRadius: 16)
    }
}

// MARK: - Buttons

/// Blue → purple capsule button.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    var height: CGFloat = 54
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(height < 50 ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(Theme.accentGradient))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Grey capsule button.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth = true
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(height < 50 ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.primary)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(Theme.fill))
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Round icon-only button (map controls, play buttons…).
struct CircleIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .background(Theme.fill, in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The floating "Add Expense | Record Memory" pill above the tab bar.
struct FloatingActionBar: View {
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 42))
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(SecondaryButtonStyle(fullWidth: false, height: 42))
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .padding(.bottom, 8)
    }
}

/// "‹ Back            [+ Action]" bar at the bottom of detail screens.
struct BackActionBar: View {
    let actionTitle: String
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(PrimaryButtonStyle(fullWidth: false, height: 44))
        }
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}

// MARK: - Chip

/// Rounded tag, e.g. "Kandy", "Outdoor", "Nine Arch Bridge".
struct Chip: View {
    let title: String
    var icon: String?
    var isSelected = false
    var tint: Color?

    init(_ title: String, icon: String? = nil, isSelected: Bool = false, tint: Color? = nil) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.subheadline.weight(isSelected ? .semibold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.primary.opacity(0.3) : Theme.stroke))
    }

    private var foreground: Color {
        if let tint { return tint }
        return isSelected ? .primary : .secondary
    }

    private var background: Color {
        if let tint { return tint.opacity(0.18) }
        return isSelected ? Color.primary.opacity(0.14) : Theme.fill
    }
}

/// Dark translucent pill used on top of photos, e.g. "Active • Day 2 of 4".
struct GlassPill: View {
    let text: String
    var icon: String?

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

/// Small coloured status pill, e.g. "● Positive", "Visited".
struct StatusBadge: View {
    let text: String
    let color: Color
    var showsDot = true

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
    }
}

struct MoodBadge: View {
    let mood: Mood

    var body: some View {
        StatusBadge(text: mood.rawValue, color: mood.color)
    }
}

/// Lays out chips left to right and wraps onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - AvatarView

/// Round avatar with the member's initials.
/// Add an image named `avatar_<name>` (e.g. `avatar_savishka`) to Assets to show a picture instead.
struct AvatarView: View {
    let member: Member
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image = UIImage(named: "avatar_\(member.name.lowercased())") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(member.color.gradient)
                    .overlay {
                        Text(member.initials)
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(member.name)
    }
}

/// Overlapping row of avatars.
struct AvatarStack: View {
    let members: [Member]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(members) { member in
                AvatarView(member: member, size: size)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
        }
    }
}

// MARK: - PhotoView

/// Shows a sample photo. Uses the asset with the same name if it exists,
/// otherwise a gradient placeholder. Always fills the space it is given.
struct PhotoView: View {
    let photo: SamplePhoto
    var showsSymbol = true

    var body: some View {
        Color.clear
            .overlay {
                if let image = UIImage(named: photo.rawValue) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(colors: photo.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            if showsSymbol {
                                Image(systemName: photo.symbol)
                                    .font(.title)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Big photo header with a back button and a status pill (Trip detail, Landmark detail).
struct HeroHeader<Content: View>: View {
    let photo: SamplePhoto
    var pill: String?
    var height: CGFloat = 340
    /// Height of the status bar, so the buttons sit below it.
    var topInset: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoView(photo: photo, showsSymbol: false)
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            content
                .foregroundStyle(.white)
                .padding(20)
        }
        .frame(height: height + topInset)
        .overlay(alignment: .top) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("Back")
                Spacer()
                if let pill {
                    GlassPill(pill)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, topInset + 8)
        }
    }
}

// MARK: - SegmentedTabs

/// Segmented control styled like the prototype (dark track, raised selected pill).
/// `dots` marks options with an orange dot, e.g. a day with a weather advisory.
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selection: Int
    var dots: Set<Int> = []
    @Namespace private var namespace

    var body: some View {
        Group {
            if options.count > 5 {
                ScrollView(.horizontal, showsIndicators: false) { row }
            } else {
                row
            }
        }
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var row: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = index }
                } label: {
                    HStack(spacing: 5) {
                        Text(options[index])
                        if dots.contains(index) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                        }
                    }
                    .font(.subheadline.weight(selection == index ? .semibold : .regular))
                    .foregroundStyle(selection == index ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, options.count > 3 ? 4 : 10)
                    .frame(minWidth: options.count > 5 ? 72 : nil, maxWidth: .infinity, minHeight: 36)
                    .background {
                        if selection == index {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.card)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(4)
    }
}

/// Circular progress ring (packing, budget).
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = .green

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring, value: progress)
    }
}
