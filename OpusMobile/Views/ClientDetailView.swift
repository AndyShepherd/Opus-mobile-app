import SwiftUI

private func openEmail(_ address: String) {
    let outlookURL = URL(string: "ms-outlook://compose?to=\(address)")
    if let outlookURL, UIApplication.shared.canOpenURL(outlookURL) {
        UIApplication.shared.open(outlookURL)
    } else if let mailto = URL(string: "mailto:\(address)") {
        UIApplication.shared.open(mailto)
    }
}

struct ClientDetailView: View {
    let customer: Customer

    @State private var appeared = false
    @State private var expandedContactIDs: Set<String> = []
    @State private var phoneSheetNumber: String?

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")
    private let goldDark = Color("GoldDark") // #4

    // #6: scaled metrics
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 76
    @ScaledMetric(relativeTo: .title) private var initialsSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var detailIconSize: CGFloat = 14

    private var kindIcon: String {
        customer.clientKind == "person" ? "person.fill" : "building.2.fill"
    }

    private var kindColor: Color {
        customer.clientKind == "person"
            ? Color(red: 0.50, green: 0.40, blue: 0.70) // #4: darker
            : Color(red: 0.20, green: 0.45, blue: 0.70) // #4: darker
    }

    private var initials: String {
        let words = customer.displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(customer.displayName.prefix(2)).uppercased()
    }

    var body: some View {
        GeometryReader { geo in // #13: geometry for proportional hero
            ScrollView {
                VStack(spacing: 0) {
                    heroHeader(maxHeight: geo.size.height)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -10)

                    VStack(spacing: 16) {
                        // Details card
                        detailsCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 15)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.15), value: appeared)

                        // Contacts
                        if !customer.contacts.isEmpty {
                            contactsCard
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 15)
                                .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.25), value: appeared)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .confirmationDialog(
            "Contact \(phoneSheetNumber ?? "")",
            isPresented: Binding(
                get: { phoneSheetNumber != nil },
                set: { if !$0 { phoneSheetNumber = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let number = phoneSheetNumber {
                let digits = number.filter { $0.isNumber || $0 == "+" }
                Button("Call") {
                    if let url = URL(string: "tel:\(digits)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("iMessage") {
                    if let url = URL(string: "sms:\(digits)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("WhatsApp") {
                    if let url = URL(string: "https://wa.me/\(digits)") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Hero Header (#13: proportional height)

    private func heroHeader(maxHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [kindColor.opacity(0.3), kindColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: avatarSize, height: avatarSize) // #6

                Text(initials)
                    .font(.system(size: initialsSize, weight: .bold, design: .rounded)) // #6
                    .foregroundColor(.white)
            }
            .shadow(color: kindColor.opacity(0.3), radius: 12, y: 4)
            .accessibilityHidden(true) // #1: name is read below

            Text(customer.displayName)
                .font(.title2.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)

            if !customer.clientId.isEmpty {
                Label(customer.clientId, systemImage: "number")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 8) {
                if !customer.type.isEmpty {
                    Label(customer.type, systemImage: kindIcon)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                // #3: status with icon, not color alone
                HStack(spacing: 3) {
                    Image(systemName: customer.active ? "checkmark.circle.fill" : "minus.circle.fill")
                        .font(.caption2)
                    Text(customer.active ? "Active" : "Inactive")
                        .font(.caption2.bold())
                }
                .foregroundColor(customer.active ? .green : .gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((customer.active ? Color.green : Color.gray).opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine) // #1
        .accessibilityLabel("\(customer.displayName), code \(customer.clientId), \(customer.type), \(customer.active ? "Active" : "Inactive")")
        .background {
            ZStack {
                LinearGradient(
                    colors: [navy, navy.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Decorative circles
                Circle()
                    .stroke(gold.opacity(0.06), lineWidth: 1)
                    .frame(width: 300, height: 300)
                Circle()
                    .stroke(gold.opacity(0.04), lineWidth: 1)
                    .frame(width: 400, height: 400)
            }
            .accessibilityHidden(true) // #1
        }
        .clipShape(
            RoundedShape(corners: [.bottomLeft, .bottomRight], radius: 28)
        )
    }

    // MARK: - Details Card

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Client Details")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if !customer.clientId.isEmpty {
                DetailCardRow(
                    icon: "number",
                    iconColor: goldDark, // #4
                    label: "Client Code",
                    value: customer.clientId,
                    iconSize: detailIconSize // #6
                )
            }

            if !customer.displayName.isEmpty {
                DetailCardRow(
                    icon: kindIcon,
                    iconColor: kindColor,
                    label: "Client Name",
                    value: customer.displayName,
                    iconSize: detailIconSize
                )
            }

            if !customer.email.isEmpty {
                TappableDetailRow(
                    icon: "envelope.fill",
                    iconColor: Color(red: 0.20, green: 0.45, blue: 0.70),
                    label: "Email",
                    value: customer.email,
                    iconSize: detailIconSize
                ) {
                    openEmail(customer.email)
                }
            }

            if !customer.phone.isEmpty {
                TappableDetailRow(
                    icon: "phone.fill",
                    iconColor: .green,
                    label: "Phone",
                    value: customer.phone,
                    iconSize: detailIconSize
                ) {
                    phoneSheetNumber = customer.phone
                }
            }

            if !customer.type.isEmpty {
                DetailCardRow(
                    icon: "briefcase.fill",
                    iconColor: Color(red: 0.50, green: 0.40, blue: 0.70), // #4
                    label: "Type",
                    value: customer.type,
                    iconSize: detailIconSize, // #6
                    isLast: true
                )
            } else {
                Spacer().frame(height: 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        )
    }

    // MARK: - Contacts Card

    private var contactsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contacts")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ForEach(Array(customer.contacts.enumerated()), id: \.element.id) { index, contact in
                let isExpanded = expandedContactIDs.contains(contact.id)
                let isLast = index == customer.contacts.count - 1

                VStack(spacing: 0) {
                    // Contact header row — tappable
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if isExpanded {
                                expandedContactIDs.remove(contact.id)
                            } else {
                                expandedContactIDs.insert(contact.id)
                            }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: 0.50, green: 0.40, blue: 0.70).opacity(0.1))
                                    .frame(width: 34, height: 34)

                                Image(systemName: "person.fill")
                                    .font(.system(size: detailIconSize, weight: .medium))
                                    .foregroundColor(Color(red: 0.50, green: 0.40, blue: 0.70))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(contact.name)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    if contact.isPrimary {
                                        Text("Primary")
                                            .font(.caption2.bold())
                                            .foregroundColor(goldDark)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(goldDark.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }

                                if !contact.role.isEmpty {
                                    Text(contact.role)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(contact.name)\(contact.role.isEmpty ? "" : ", \(contact.role)")\(contact.isPrimary ? ", Primary contact" : "")")
                    .accessibilityHint(isExpanded ? "Double tap to collapse" : "Double tap to show contact details")

                    // Expanded contact details
                    if isExpanded {
                        VStack(spacing: 0) {
                            if !contact.phone.isEmpty {
                                contactActionRow(icon: "phone.fill", label: "Phone", value: contact.phone, color: .green) {
                                    phoneSheetNumber = contact.phone
                                }
                            }

                            if !contact.mobile.isEmpty {
                                contactActionRow(icon: "iphone", label: "Mobile", value: contact.mobile, color: Color(red: 0.20, green: 0.45, blue: 0.70)) {
                                    phoneSheetNumber = contact.mobile
                                }
                            }

                            if !contact.email.isEmpty {
                                contactActionRow(icon: "envelope.fill", label: "Email", value: contact.email, color: Color(red: 0.20, green: 0.45, blue: 0.70)) {
                                    openEmail(contact.email)
                                }
                            }
                        }
                        .padding(.leading, 48)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !isLast {
                        Divider()
                            .padding(.leading, 68)
                    } else {
                        Spacer().frame(height: 8)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        )
    }

    private func contactActionRow(icon: String, label: String, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(color)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.trailing, 20)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint("Double tap to \(label == "Email" ? "send email" : "call")")
    }
}

// MARK: - Tappable Detail Row

private struct TappableDetailRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var iconSize: CGFloat = 14
    var isLast: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(iconColor.opacity(0.1))
                            .frame(width: 34, height: 34)

                        Image(systemName: icon)
                            .font(.system(size: iconSize, weight: .medium))
                            .foregroundColor(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(value)
                            .font(.body)
                            .foregroundColor(iconColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label): \(value)")
            .accessibilityHint("Double tap to \(label == "Email" ? "send email" : "contact this number")")

            if !isLast {
                Divider()
                    .padding(.leading, 68)
            } else {
                Spacer().frame(height: 8)
            }
        }
    }
}

// MARK: - Detail Card Row

private struct DetailCardRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    var iconSize: CGFloat = 14
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 34, height: 34)

                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .medium)) // #6
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(value)
                        .font(.body)
                        .foregroundColor(.primary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine) // #1
            .accessibilityLabel("\(label): \(value)")

            if !isLast {
                Divider()
                    .padding(.leading, 68)
            } else {
                Spacer().frame(height: 8)
            }
        }
    }
}

// MARK: - Rounded Shape Helper

private struct RoundedShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
