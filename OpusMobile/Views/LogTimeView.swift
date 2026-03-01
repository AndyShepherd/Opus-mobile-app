import SwiftUI

struct LogTimeView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    /// Pre-filled customer (from ClientDetailView). When set, the client picker is disabled.
    private let prefilledCustomer: Customer?
    private let onSave: () -> Void

    @State private var workType: WorkType = .client
    @State private var selectedCustomer: Customer?
    @State private var selectedServiceCode = ""
    @State private var selectedActivityCode = ""
    @State private var date = Date()
    @State private var units = 1
    @State private var notes = ""

    @State private var customers: [Customer] = []
    @State private var services: [ServiceDefinition] = []
    @State private var activities: [NonClientActivity] = []
    @State private var isSaving = false
    @State private var isLoadingData = false
    @State private var saveError: String?

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")
    private let goldDark = Color("GoldDark")

    private enum WorkType: String, CaseIterable {
        case client = "Client"
        case nonClient = "Non-Client"
    }

    /// General init — from TimeEntryListView
    init(onSave: @escaping () -> Void) {
        self.prefilledCustomer = nil
        self.onSave = onSave
    }

    /// Pre-filled init — from ClientDetailView
    init(customer: Customer, onSave: @escaping () -> Void) {
        self.prefilledCustomer = customer
        self.onSave = onSave
    }

    private var isValid: Bool {
        switch workType {
        case .client:
            return selectedCustomer != nil
        case .nonClient:
            return !selectedActivityCode.isEmpty
        }
    }

    private var durationText: String {
        let totalMinutes = units * 15
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60
        return "\(units) units (\(hrs) hrs \(mins) min)"
    }

    var body: some View {
        Form {
            // Work type
            Section {
                Picker("Type", selection: $workType) {
                    ForEach(WorkType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .disabled(prefilledCustomer != nil)
            }

            // Client / Activity section
            if workType == .client {
                Section("Client") {
                    if let prefilled = prefilledCustomer {
                        HStack {
                            Text(prefilled.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Select Client", selection: $selectedCustomer) {
                            Text("Choose...").tag(nil as Customer?)
                            ForEach(customers) { customer in
                                Text(customer.displayName).tag(customer as Customer?)
                            }
                        }
                    }

                    if !services.isEmpty {
                        Picker("Service", selection: $selectedServiceCode) {
                            Text("None").tag("")
                            ForEach(services) { service in
                                Text(service.name).tag(service.code)
                            }
                        }
                    }
                }
            } else {
                Section("Activity") {
                    if isLoadingData {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Picker("Select Activity", selection: $selectedActivityCode) {
                            Text("Choose...").tag("")
                            ForEach(activities) { activity in
                                Text(activity.name).tag(activity.code)
                            }
                        }
                    }
                }
            }

            // Date & Duration
            Section("Date & Duration") {
                DatePicker("Date", selection: $date, displayedComponents: .date)

                Stepper(value: $units, in: 1...96) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration")
                            .font(.body)
                        Text(durationText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Notes
            Section("Notes") {
                TextField("Optional notes...", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Save
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Entry")
                                .font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .disabled(!isValid || isSaving)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isValid && !isSaving ? gold : gold.opacity(0.4))
                )
                .foregroundColor(.white)
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Log Time")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            if let prefilled = prefilledCustomer {
                selectedCustomer = prefilled
                workType = .client
            }
        }
        .task {
            await loadFormData()
        }
    }

    // MARK: - Data

    private func loadFormData() async {
        isLoadingData = true

        // Load clients from cache first, fall back to API
        if let cached = ClientCache.load() {
            customers = cached.customers.sorted { $0.displayName < $1.displayName }
        }

        async let fetchedServices: [ServiceDefinition] = authService.authenticatedRequest(
            path: "/api/services"
        )
        async let fetchedActivities: [NonClientActivity] = authService.authenticatedRequest(
            path: "/api/time/activities"
        )

        do {
            let (svc, act) = try await (fetchedServices, fetchedActivities)
            services = svc.filter(\.isActive)
            activities = act.filter(\.isActive)
        } catch {
            // Non-fatal — pickers may be empty but form still works for basic entries
        }

        // If cache was empty, try API
        if customers.isEmpty {
            do {
                let fetched: [Customer] = try await authService.authenticatedRequest(
                    path: "/api/customers"
                )
                customers = fetched.sorted { $0.displayName < $1.displayName }
            } catch {
                // Non-fatal
            }
        }

        isLoadingData = false
    }

    private func save() async {
        isSaving = true
        saveError = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)

        let customer = prefilledCustomer ?? selectedCustomer

        let payload = TimeEntryPayload(
            date: formatter.string(from: date),
            units: units,
            customerId: workType == .client ? (customer?.id ?? "") : "",
            serviceCode: workType == .client ? selectedServiceCode : "",
            activityCode: workType == .nonClient ? selectedActivityCode : "",
            notes: notes
        )

        do {
            let body = try JSONEncoder().encode(payload)
            let _: TimeEntry = try await authService.authenticatedRequest(
                path: "/api/time/entries",
                method: "POST",
                body: body
            )
            onSave()
            dismiss()
        } catch APIError.unauthorized {
            // Already handled
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }
}
