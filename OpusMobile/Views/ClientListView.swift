import SwiftUI

struct ClientListView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var customers: [Customer] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeFilter: FilterKind = .all

    private enum FilterKind: String, CaseIterable {
        case all = "Total"
        case active = "Active"
        case companies = "Companies"
        case individuals = "Individuals"
    }

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")
    // Darker gold variant that meets WCAG contrast requirements on white/light backgrounds
    private let goldDark = Color("GoldDark")

    /// Filtered and sorted client list. Reversed so newest clients appear first
    /// (the API returns oldest-first). Category filter and search are applied in sequence.
    private var filtered: [Customer] {
        var result = customers.reversed() as [Customer]

        // Category filter from the stats banner chips
        switch activeFilter {
        case .all: break
        case .active: result = result.filter(\.active)
        case .companies: result = result.filter { $0.clientKind != "person" }
        case .individuals: result = result.filter { $0.clientKind == "person" }
        }

        // Free-text search across multiple fields for quick lookup
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.clientId.lowercased().contains(query) ||
                $0.name.lowercased().contains(query) ||
                $0.company.lowercased().contains(query) ||
                $0.email.lowercased().contains(query) ||
                $0.phone.lowercased().contains(query)
            }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Group {
                    if isLoading && customers.isEmpty {
                        loadingView
                    } else if let errorMessage, customers.isEmpty {
                        errorView(errorMessage)
                    } else if customers.isEmpty {
                        emptyView
                    } else if filtered.isEmpty && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        clientList
                    }
                }
            }
            .navigationTitle("Clients")
            .navigationDestination(for: Customer.self) { customer in
                ClientDetailView(customer: customer)
            }
            .searchable(text: $searchText, prompt: "Search by code, name, email, phone")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("OpusLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                        // Decorative — the nav title "Clients" provides the label
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }

                        Button(role: .destructive) {
                            withAnimation {
                                authService.logout()
                            }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .accessibilityLabel("Account menu")
                }
            }
            .toolbarBackground(navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // .task (not .onAppear) provides structured concurrency — auto-cancels if the view disappears
            .task { await fetchClients() }
        }
        .tint(gold)
    }

    // MARK: - Client List
    // Uses List (not ScrollView+LazyVStack) to get native pull-to-refresh, swipe actions,
    // and automatic cell reuse. Custom row backgrounds give it a card-style appearance.

    private var clientList: some View {
        List {
            // Stats banner
            if !customers.isEmpty && searchText.isEmpty {
                statsBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            ForEach(filtered) { customer in
                NavigationLink(value: customer) {
                    ClientRow(customer: customer)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color("CardBackground"))
                        .padding(.vertical, 4)
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                // Combine child elements into one VoiceOver item with a structured label
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabelFor(customer))
                .accessibilityHint("Double tap to view client details")
            }
        }
        .listStyle(.plain)
        .refreshable { await fetchClients() }
    }

    /// Builds a VoiceOver label like "Acme Ltd, code ABC001, Limited Company, Active"
    /// so screen reader users get all key info without navigating child elements.
    private func accessibilityLabelFor(_ customer: Customer) -> String {
        var parts: [String] = []
        parts.append(customer.displayName)
        if !customer.clientId.isEmpty { parts.append("code \(customer.clientId)") }
        if !customer.type.isEmpty { parts.append(customer.type) }
        // Active/inactive status included because it's not conveyed by colour alone
        parts.append(customer.active ? "Active" : "Inactive")
        return parts.joined(separator: ", ")
    }

    // MARK: - Stats Banner

    private var statsBanner: some View {
        let activeCount = customers.filter(\.active).count
        let companyCount = customers.filter { $0.clientKind != "person" }.count
        let personCount = customers.filter { $0.clientKind == "person" }.count

        return HStack(spacing: 0) {
            StatChip(value: "\(customers.count)", label: "Total", icon: "person.2.fill", color: goldDark, isSelected: activeFilter == .all) {
                withAnimation(.easeInOut(duration: 0.2)) { activeFilter = activeFilter == .all ? .all : .all }
            }
            Spacer()
            StatChip(value: "\(activeCount)", label: "Active", icon: "checkmark.circle.fill", color: .green, isSelected: activeFilter == .active) {
                withAnimation(.easeInOut(duration: 0.2)) { activeFilter = activeFilter == .active ? .all : .active }
            }
            Spacer()
            StatChip(value: "\(companyCount)", label: "Companies", icon: "building.2.fill", color: Color(red: 0.20, green: 0.45, blue: 0.70), isSelected: activeFilter == .companies) {
                withAnimation(.easeInOut(duration: 0.2)) { activeFilter = activeFilter == .companies ? .all : .companies }
            }
            Spacer()
            StatChip(value: "\(personCount)", label: "Individuals", icon: "person.fill", color: Color(red: 0.50, green: 0.40, blue: 0.70), isSelected: activeFilter == .individuals) {
                withAnimation(.easeInOut(duration: 0.2)) { activeFilter = activeFilter == .individuals ? .all : .individuals }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        // Collapsed into a single VoiceOver element with a summary label below
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Client summary: \(customers.count) total, \(activeCount) active, \(companyCount) companies, \(personCount) individuals")
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(gold)
            Text("Loading clients...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Clients", systemImage: "person.2.slash")
        } description: {
            Text("No clients have been added yet.")
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        // Wrapped in ScrollView so pull-to-refresh works even on the error state
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 100)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundColor(goldDark.opacity(0.6))
                    .accessibilityHidden(true)

                Text("Connection Error")
                    .font(.title3.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await fetchClients() }
                } label: {
                    Text("Try Again")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(gold)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await fetchClients() }
    }

    // MARK: - Data

    private func fetchClients() async {
        guard let token = authService.token else { return }
        isLoading = true
        errorMessage = nil

        do {
            customers = try await APIClient.request(
                path: "/api/customers",
                token: token
            )
        } catch APIError.unauthorized {
            authService.logout()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var isSelected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.footnote)
                    .foregroundColor(color)

                Text(value)
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundColor(.primary)

                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint("Double tap to filter by \(label.lowercased())")
    }
}

// MARK: - Client Row

private struct ClientRow: View {
    let customer: Customer

    private let gold = Color("BrandGold")

    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var initialsSize: CGFloat = 15

    // Distinct colours for individuals (purple) vs companies (blue) — darker variants
    // chosen to meet WCAG contrast requirements against the white card background
    private var kindColor: Color {
        customer.clientKind == "person"
            ? Color(red: 0.50, green: 0.40, blue: 0.70)
            : Color(red: 0.20, green: 0.45, blue: 0.70)
    }

    private var initials: String {
        let words = customer.displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(customer.displayName.prefix(2)).uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [kindColor.opacity(0.2), kindColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(initials)
                    .font(.system(size: initialsSize, weight: .bold, design: .rounded))
                    .foregroundColor(kindColor)
            }
            .frame(width: avatarSize, height: avatarSize)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(customer.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    // Allows long names to shrink rather than truncate
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    if !customer.clientId.isEmpty {
                        Text(customer.clientId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !customer.type.isEmpty {
                        Text(customer.type)
                            .font(.caption2)
                            .foregroundColor(kindColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(kindColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // Status uses both icon and text so it's not conveyed by colour alone (WCAG)
            HStack(spacing: 4) {
                Image(systemName: customer.active ? "checkmark.circle.fill" : "minus.circle.fill")
                    .font(.caption2)
                    .foregroundColor(customer.active ? .green : .secondary)

                Text(customer.active ? "Active" : "Inactive")
                    .font(.caption2)
                    .foregroundColor(customer.active ? .green : .secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 6)
    }
}
