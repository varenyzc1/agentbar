import SwiftUI

enum AgentBarStyle {
    static let green = Color(red: 0.00, green: 0.48, blue: 0.18)
    static let yellow = Color(red: 0.78, green: 0.55, blue: 0.08)
    static let red = Color(red: 0.78, green: 0.14, blue: 0.12)
    static let greenSoft = Color(red: 0.86, green: 0.95, blue: 0.89)
    static let greenSoftDark = Color(red: 0.08, green: 0.22, blue: 0.13)

    static func panelBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.082, blue: 0.094)
            : Color(red: 0.955, green: 0.968, blue: 0.978)
    }

    static func cardBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.125, green: 0.135, blue: 0.152)
            : Color(red: 0.992, green: 0.996, blue: 1.00)
    }

    static func raisedBackground(_ colorScheme: ColorScheme, pressed: Bool = false) -> Color {
        if colorScheme == .dark {
            return pressed ? Color(red: 0.18, green: 0.20, blue: 0.22) : Color(red: 0.145, green: 0.155, blue: 0.175)
        }
        return pressed ? Color(red: 0.89, green: 0.92, blue: 0.94) : Color(red: 0.975, green: 0.985, blue: 0.992)
    }

    static func fieldBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.095, green: 0.105, blue: 0.122)
            : Color(red: 0.965, green: 0.976, blue: 0.984)
    }

    static func stroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.235, green: 0.255, blue: 0.285)
            : Color(red: 0.82, green: 0.86, blue: 0.895)
    }

    static func selectedBackground(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? greenSoftDark : greenSoft
    }

    static func track(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.27, blue: 0.30)
            : Color(red: 0.86, green: 0.89, blue: 0.91)
    }

    static func primaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.95, blue: 0.96)
            : Color(red: 0.04, green: 0.045, blue: 0.05)
    }

    static func secondaryText(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.68, blue: 0.70)
            : Color(red: 0.43, green: 0.44, blue: 0.46)
    }
}

struct AgentBarPanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(AgentBarStyle.panelBackground(colorScheme))
    }
}

struct AgentBarCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .fill(AgentBarStyle.cardBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .circular)
                    .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
            )
    }
}

extension View {
    func agentBarPanelBackground() -> some View {
        modifier(AgentBarPanelBackground())
    }

    func agentBarCard(padding: CGFloat = 10) -> some View {
        modifier(AgentBarCardStyle(padding: padding))
    }

    func agentBarPrimaryText() -> some View {
        modifier(AgentBarTextColorStyle(kind: .primary))
    }

    func agentBarSecondaryText() -> some View {
        modifier(AgentBarTextColorStyle(kind: .secondary))
    }
}

struct AgentBarTextColorStyle: ViewModifier {
    enum Kind {
        case primary
        case secondary
    }

    @Environment(\.colorScheme) private var colorScheme
    let kind: Kind

    func body(content: Content) -> some View {
        switch kind {
        case .primary:
            content.foregroundStyle(AgentBarStyle.primaryText(colorScheme))
        case .secondary:
            content.foregroundStyle(AgentBarStyle.secondaryText(colorScheme))
        }
    }
}

struct AgentBarIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .agentBarPrimaryText()
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill(AgentBarStyle.raisedBackground(colorScheme, pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .circular))
    }
}

struct AgentBarCommandButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .agentBarPrimaryText()
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill(AgentBarStyle.raisedBackground(colorScheme, pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
            )
    }
}

struct AgentBarTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.caption.monospacedDigit())
            .textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .fill(AgentBarStyle.fieldBackground(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .circular)
                    .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
            )
    }
}

struct AgentBarProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let clamped = max(0, min(1, value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AgentBarStyle.track(colorScheme))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * clamped))
            }
        }
        .frame(height: 6)
    }
}

struct AgentBarCheckbox: View {
    @Environment(\.colorScheme) private var colorScheme
    let isOn: Bool

    var body: some View {
        Image(systemName: isOn ? "checkmark.square.fill" : "square")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? AgentBarStyle.green : AgentBarStyle.secondaryText(colorScheme))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}

struct AgentBarSwitch: View {
    @Environment(\.colorScheme) private var colorScheme
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AgentBarStyle.green : AgentBarStyle.track(colorScheme))
            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.16), radius: 1, x: 0, y: 1)
                .padding(2)
        }
        .frame(width: 36, height: 20)
        .overlay(
            Capsule()
                .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 0.8)
        )
        .contentShape(Capsule())
    }
}

struct AgentBarSegmentedPicker<Option: Identifiable & Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(selection == option ? AgentBarStyle.green : AgentBarStyle.secondaryText(colorScheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .padding(.horizontal, 6)
                        .background(segmentBackground(for: option))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .circular)
                .fill(AgentBarStyle.fieldBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .circular)
                .stroke(AgentBarStyle.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func segmentBackground(for option: Option) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .circular)
            .fill(selection == option ? AgentBarStyle.selectedBackground(colorScheme) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .circular)
                    .stroke(selection == option ? AgentBarStyle.green.opacity(0.25) : Color.clear, lineWidth: 0.8)
            )
    }
}
