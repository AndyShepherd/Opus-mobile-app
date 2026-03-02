import SwiftUI

struct ClientListView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var customers: [Customer] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var activeFilter: FilterKind = .active
    @State private var lastUpdated: Date?

    // Pagination
    @State private var currentPage = 1
    @State private var totalItems = 0
    @State private var hasMorePages = false

    // Cancellation / debounce
    @State private var currentFetchTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?

    // Throttle full-cache refresh (for LogTimeView picker) to every 5 minutes
    @State private var lastFullCacheRefresh: Date?

    private static let pageSize = 50

    private enum FilterKind: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case companies = "Companies"
        case individuals = "Individuals"
    }

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")
    private let goldDark = Color("GoldDark")

    /// Client-side filter for Companies/Individuals chips (backend lacks `clientKind` param).
    /// Active and All filters are handled server-side, so no client-side filtering needed.
    private var filtered: [Customer] {
        switch activeFilter {
        case .all, .active:
            return customers
        case .companies:
            return customers.filter { $0.clientKind != "person" }
        case .individuals:
            return customers.filter { $0.clientKind == "person" }
        }
    }

    /// Filter key for page caching — identifies the server-side query parameters.
    private var filterKey: String {
        let activeParam = activeFilter == .active ? "true" : ""
        return "search=\(searchText)&active=\(activeParam)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && customers.isEmpty {
                    loadingView
                } else if let errorMessage, customers.isEmpty {
                    errorView(errorMessage)
                } else if customers.isEmpty {
                    emptyView
                } else if filtered.isEmpty {
                    if !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView {
                            Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No clients match the selected filter.")
                        }
                    }
                } else {
                    clientList
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Clients")
            .navigationDestination(for: Customer.self) { customer in
                ClientDetailView(customer: customer)
            }
            .searchable(text: $searchText, prompt: "Search by code, name, email, phone")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await applyFilter()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        NavigationLink {
                            TimeEntryListView()
                        } label: {
                            Label("Time Entries", systemImage: "clock")
                        }
                    } label: {
                        Image("OpusLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 30)
                    }
                    .accessibilityLabel("Navigation menu")
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await fetchClients() }
        }
    }

    // MARK: - Client List

    private var clientList: some View {
        List {
            // Stats banner
            if !customers.isEmpty && searchText.isEmpty {
                statsBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                if let lastUpdated {
                    Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }
            }

            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, customer in
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabelFor(customer))
                .accessibilityHint("Double tap to view client details")
                .onAppear {
                    // Trigger next page load when 10 items from the bottom
                    if index >= filtered.count - 10 {
                        loadMoreIfNeeded()
                    }
                }
            }

            // Bottom loading spinner for infinite scroll
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(gold)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await applyFilter()
        }
    }

    private func accessibilityLabelFor(_ customer: Customer) -> String {
        var parts: [String] = []
        parts.append(customer.displayName)
        if !customer.clientId.isEmpty { parts.append("code \(customer.clientId)") }
        if !customer.type.isEmpty { parts.append(customer.type) }
        parts.append(customer.active ? "Active" : "Inactive")
        return parts.joined(separator: ", ")
    }

    // MARK: - Stats Banner

    private var statsBanner: some View {
        HStack(spacing: 0) {
            StatChip(label: "All", icon: "person.2.fill", color: goldDark, isSelected: activeFilter == .all) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    guard activeFilter != .all else { return }
                    activeFilter = .all
                    Task { await applyFilter() }
                }
            }
            Spacer()
            StatChip(label: "Active", icon: "checkmark.circle.fill", color: .green, isSelected: activeFilter == .active) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    guard activeFilter != .active else { return }
                    activeFilter = .active
                    Task { await applyFilter() }
                }
            }
            Spacer()
            StatChip(label: "Companies", icon: "building.2.fill", color: Color(red: 0.20, green: 0.45, blue: 0.70), isSelected: activeFilter == .companies) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    guard activeFilter != .companies else { return }
                    activeFilter = .companies
                    Task { await applyFilter() }
                }
            }
            Spacer()
            StatChip(label: "Individuals", icon: "person.fill", color: Color(red: 0.50, green: 0.40, blue: 0.70), isSelected: activeFilter == .individuals) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    guard activeFilter != .individuals else { return }
                    activeFilter = .individuals
                    Task { await applyFilter() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Client filters: All, Active, Companies, Individuals. Currently showing \(activeFilter.rawValue)")
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

    /// Builds the URL path with pagination and filter query parameters.
    private func buildURL(page: Int) -> String {
        var components = URLComponents(string: "/api/customers")!
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(Self.pageSize)"),
            URLQueryItem(name: "sort", value: "displayName"),
            URLQueryItem(name: "order", value: "asc"),
        ]

        if !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: searchText))
        }

        if activeFilter == .active {
            queryItems.append(URLQueryItem(name: "active", value: "true"))
        }

        components.queryItems = queryItems
        return components.string ?? "/api/customers"
    }

    /// Cancels any in-flight fetch, resets to page 1, and re-fetches.
    private func applyFilter() async {
        currentFetchTask?.cancel()
        currentPage = 1
        hasMorePages = false
        await fetchClients()
    }

    /// Fetches page 1. Loads from page cache on first call for instant startup.
    private func fetchClients() async {
        // Load from page cache on first call so clients appear instantly
        if customers.isEmpty {
            if let cached = ClientCache.loadPage(filterKey: filterKey) {
                customers = cached.customers
                totalItems = cached.total
                hasMorePages = customers.count < cached.total
                lastUpdated = cached.lastUpdated
            }
        }

        isLoading = true
        errorMessage = nil
        currentPage = 1

        let task = Task {
            do {
                let response: PaginatedResponse<Customer> = try await authService.authenticatedRequest(
                    path: buildURL(page: 1)
                )
                guard !Task.isCancelled else { return }
                customers = response.items
                totalItems = response.total
                currentPage = 1
                hasMorePages = response.items.count < response.total
                lastUpdated = Date()

                // Cache page 1 for instant startup
                ClientCache.savePage(response.items, total: response.total, filterKey: filterKey)

                // Refresh the full client cache for LogTimeView picker (throttled to every 5 min)
                await refreshFullCacheIfNeeded()
            } catch APIError.unauthorized {
                // authenticatedRequest already handled logout
            } catch {
                guard !Task.isCancelled else { return }
                if customers.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
        currentFetchTask = task
        await task.value
        isLoading = false
    }

    /// Fetches the next page and appends results.
    private func fetchNextPage() async {
        let nextPage = currentPage + 1
        isLoadingMore = true

        let task = Task {
            do {
                let response: PaginatedResponse<Customer> = try await authService.authenticatedRequest(
                    path: buildURL(page: nextPage)
                )
                guard !Task.isCancelled else { return }
                customers.append(contentsOf: response.items)
                currentPage = nextPage
                hasMorePages = customers.count < response.total
                totalItems = response.total
            } catch APIError.unauthorized {
                // handled by authenticatedRequest
            } catch {
                // Silently fail — user can scroll up and try again
            }
        }
        currentFetchTask = task
        await task.value
        isLoadingMore = false
    }

    /// Triggers next page load if there are more pages and we're not already loading.
    private func loadMoreIfNeeded() {
        guard hasMorePages, !isLoadingMore, !isLoading else { return }
        Task { await fetchNextPage() }
    }

    /// Refreshes the full client cache (all clients, no pagination) for the LogTimeView picker.
    /// Throttled to at most once every 5 minutes.
    private func refreshFullCacheIfNeeded() async {
        if let last = lastFullCacheRefresh, Date().timeIntervalSince(last) < 300 {
            return
        }
        do {
            let allClients: [Customer] = try await authService.authenticatedRequest(
                path: "/api/customers"
            )
            ClientCache.save(allClients)
            lastFullCacheRefresh = Date()
        } catch {
            // Non-fatal — the existing full cache remains valid
        }
    }
}

// MARK: - Stat Chip

private struct StatChip: View {
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

                Text(label)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
        .accessibilityLabel(label)
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

            VStack(alignment: .leading, spacing: 3) {
                Text(customer.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
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
