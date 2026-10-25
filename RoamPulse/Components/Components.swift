import SwiftUI

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

extension EnvironmentValues {
    // True for the first screen of the iPad detail column, where there's nothing to go back to
    @Entry var isDetailRoot = false
}

extension View {
    // These screens draw their own header, so the bar is hidden on iPhone. At the top of the iPad
    // detail column it stays, because it holds the button that shows the sidebar again
    func navigationBarHiddenOnPhone() -> some View {
        modifier(PhoneOnlyHiddenBar())
    }
}

private struct PhoneOnlyHiddenBar: ViewModifier {
    @Environment(\.isDetailRoot) private var isDetailRoot

    func body(content: Content) -> some View {
        content
            .toolbar(isDetailRoot ? .visible : .hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct BackActionBar: View {
    let actionTitle: String
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDetailRoot) private var isDetailRoot

    var body: some View {
        HStack {
            if !isDetailRoot {
                Button {
                    dismiss()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
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
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.45), in: Capsule())
    }
}

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

// Shows initials, or an avatar_<name> image from Assets if there is one
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

// Uses the asset with this name, or a gradient if it's missing
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

struct HeroHeader<Content: View>: View {
    let photo: SamplePhoto
    // If set, show this trip's cover instead of photo
    var trip: Trip?
    var pill: String?
    var height: CGFloat = 340
    var topInset: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDetailRoot) private var isDetailRoot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let trip {
                TripCoverView(trip: trip, showsSymbol: false)
            } else {
                PhotoView(photo: photo, showsSymbol: false)
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            content
                .foregroundStyle(.white)
                .padding(20)
        }
        .frame(height: height + topInset)
        .overlay(alignment: .top) {
            HStack {
                if !isDetailRoot {
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
                }
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

// dots = days with a weather warning, onDrop lets activities be dragged onto a day
struct SegmentedTabs: View {
    let options: [String]
    @Binding var selection: Int
    var dots: Set<Int> = []
    var onDrop: ((Int, [String]) -> Bool)?
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
                .modifier(DropTarget(index: index, onDrop: onDrop))
            }
        }
        .padding(4)
    }
}

private struct DropTarget: ViewModifier {
    let index: Int
    let onDrop: ((Int, [String]) -> Bool)?
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        if let onDrop {
            content
                .dropDestination(for: String.self) { items, _ in
                    onDrop(index, items)
                } isTargeted: { isTargeted = $0 }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.blue, lineWidth: isTargeted ? 2 : 0)
                }
        } else {
            content
        }
    }
}

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

extension View {
    func errorAlert(_ store: TripStore, isEnabled: Bool = true) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { isEnabled && store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // Puts everything the previews need into the environment
    func previewEnvironment(_ dependencies: AppDependencies) -> some View {
        environment(dependencies)
            .environment(dependencies.store)
            .environment(dependencies.session)
            .environment(dependencies.reminders)
            .environment(dependencies.appLock)
            .environment(dependencies.voice)
            .environment(dependencies.location)
            .environment(dependencies.geofences)
            .environment(AppRouter())
            .preferredColorScheme(.dark)
    }
}
