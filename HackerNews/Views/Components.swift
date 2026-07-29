import SwiftUI

/// Full-screen placeholder for empty lists.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.hnOrange)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: 380)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: "exclamationmark.triangle",
            title: "Something went wrong",
            message: message,
            actionTitle: "Try Again",
            action: retry
        )
    }
}

/// Centred spinner used while a screen has nothing to show yet.
struct LoadingStateView: View {
    var label: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let label {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Row placed at the bottom of a paginated list; loads the next page when it
/// scrolls into view.
struct LoadMoreRow: View {
    let onAppear: () -> Void

    var body: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 10)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .onAppear(perform: onAppear)
        .accessibilityLabel("Loading more")
    }
}

/// Small coloured square with the source's initial — gives link posts a
/// recognisable shape in the list without fetching remote favicons.
struct SourceBadge: View {
    let label: String
    let seed: String
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color.stableColor(for: seed).opacity(0.16))
            .overlay(
                Text(label)
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.stableColor(for: seed))
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// `12 points`-style metadata chip.
struct MetaLabel: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(tint)
    }
}

/// A tappable pill used for the feed switcher and search filters.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    isSelected
                        ? Color.hnOrange.opacity(0.16)
                        : Color(uiColor: .secondarySystemBackground)
                )
            )
            .foregroundColor(isSelected ? .hnOrange : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
