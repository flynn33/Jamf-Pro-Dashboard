import SwiftUI

private enum SupportTechnicianLayout {
    static let controlButtonHeight: CGFloat = 50
}

private enum SupportTechnicianDetailPane: Hashable {
    case device
    case applicationManager
    case diagnostics
    case certificateManager
    case accountManager
    case mobilePINControl
    case configurationProfileManager
    case groupMembershipManager
}

/// SupportTechnicianView declaration.
struct SupportTechnicianView: View {
    @StateObject private var viewModel: SupportTechnicianViewModel
    @State private var pendingConfirmationAction: SupportManagementAction?
    @State private var pendingTypedRemovalAction: SupportManagementAction?
    @State private var typedRemovalConfirmationText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailPaneHistory: [SupportTechnicianDetailPane] = [.device]

    private var detailPane: SupportTechnicianDetailPane {
        detailPaneHistory.last ?? .device
    }

    /// Initializes the instance.
    init(viewModel: SupportTechnicianViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("Name, username, or serial number", text: $viewModel.query)
                            .textFieldStyle(.roundedBorder)
                            .appNoAutoCorrectionTextInput()
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await viewModel.executeSearch()
                                }
                            }

                        ScanIntoTextFieldButton(text: $viewModel.query)

                        SupportInfoButton(
                            title: "Asset Query",
                            helpText: "Search by device name, username, or serial number. Scanner input can be used for barcode workflows."
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Search Scope")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            SupportInfoButton(
                                title: "Search Scope",
                                helpText: "All searches both Computers and Mobile devices. Narrow scope to reduce noise and improve speed."
                            )
                        }

                        Picker("Scope", selection: $viewModel.searchScope) {
                            ForEach(SupportSearchScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await viewModel.executeSearch()
                            }
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                        .disabled(viewModel.isSearching)

                        SupportInfoButton(
                            title: "Run Search",
                            helpText: "Loads matching assets into Results. Selecting a result opens full diagnostics and controls in the device pane."
                        )
                    }
                } header: {
                    SupportSectionHeader(
                        title: "Search",
                        helpText: "Find a managed device and open the technician device view."
                    )
                }

                if viewModel.isSearching {
                    Section {
                        ProgressView("Searching Jamf Pro...")
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if viewModel.searchResults.isEmpty {
                        Text("No results yet. Run a search to find managed assets.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.searchResults) { result in
                            Button {
                                detailPaneHistory = [.device]
                                viewModel.selectedResultID = result.id
                            } label: {
                                SupportSearchResultRow(
                                    result: result,
                                    isSelected: viewModel.selectedResultID == result.id
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoadingDetail || viewModel.isSearching)
                        }
                    }
                } header: {
                    SupportSectionHeader(
                        title: "Results",
                        helpText: "Choose one result to load prioritized device identity, health diagnostics, and management actions."
                    )
                }
            }
            .appInsetGroupedListStyle()
            .navigationTitle("Support Technician")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 430, ideal: 500, max: 620)
#endif
        } detail: {
            switch detailPane {
            case .device:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportDeviceDetailView(
                        detail: selectedDetail,
                        actions: viewModel.availableActions,
                        availableApplications: viewModel.availableApplications,
                        isLoadingDetail: viewModel.isLoadingDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        isLoadingApplications: viewModel.isLoadingApplications,
                        isPerformingApplicationCommand: viewModel.isPerformingApplicationCommand,
                        actionResult: viewModel.actionResult,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        canGoBack: detailPaneHistory.count > 1,
                        onGoBack: {
                            popDetailPane()
                        },
                        onRefresh: {
                            Task {
                                await viewModel.refreshSelectedDeviceDetail()
                            }
                        },
                        onAction: { action in
                            pendingConfirmationAction = action
                        },
                        onOpenApplicationManager: {
                            pushDetailPane(.applicationManager)
                            Task {
                                await viewModel.loadApplicationsForSelectedDevice()
                            }
                        },
                        onOpenDiagnosticView: {
                            pushDetailPane(.diagnostics)
                        },
                        onOpenCertificateManager: {
                            pushDetailPane(.certificateManager)
                        },
                        onOpenAccountManager: {
                            pushDetailPane(.accountManager)
                        },
                        onOpenMobilePINControl: {
                            pushDetailPane(.mobilePINControl)
                        },
                        onOpenConfigurationProfileManager: {
                            pushDetailPane(.configurationProfileManager)
                        },
                        onOpenGroupMembershipManager: {
                            pushDetailPane(.groupMembershipManager)
                        }
                    )
                    .navigationTitle(selectedDetail.summary.displayName)
                    .appInlineNavigationTitle()
                } else if viewModel.isLoadingDetail {
                    ProgressView("Loading device detail...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "wrench.and.screwdriver",
                        description: "Select a search result to load diagnostics, full device data, and management actions.",
                        onGoBack: nil
                    )
                }
            case .applicationManager:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportApplicationManagerView(
                        deviceName: selectedDetail.summary.displayName,
                        applications: viewModel.availableApplications,
                        isLoadingApplications: viewModel.isLoadingApplications,
                        isPerformingCommand: viewModel.isPerformingApplicationCommand,
                        isPerformingManagementAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        commandProvider: { application in
                            viewModel.applicationCommands(for: application)
                        },
                        onGoBack: {
                            popDetailPane()
                        },
                        onReload: {
                            Task {
                                await viewModel.loadApplicationsForSelectedDevice()
                            }
                        },
                        onDiscoverApplications: {
                            Task {
                                await viewModel.discoverApplicationsFromApplicationManager()
                            }
                        },
                        onUpdateOperatingSystem: {
                            Task {
                                await viewModel.performAction(.updateOperatingSystem)
                            }
                        },
                        onCommand: { command, application in
                            Task {
                                await viewModel.performApplicationCommand(command, for: application)
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "app.badge",
                        description: "Select a device in Results before opening Application Manager.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .diagnostics:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportDeviceDiagnosticsView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        latestDeviceLogs: viewModel.latestDeviceLogs,
                        onGoBack: {
                            popDetailPane()
                        },
                        onRefreshDiagnostics: {
                            Task {
                                await viewModel.refreshSelectedDeviceDetail()
                            }
                        },
                        onRequestErrorLogs: {
                            Task {
                                await viewModel.requestDeviceErrorLogs()
                            }
                        },
                        onUpdateOperatingSystem: {
                            pendingConfirmationAction = .updateOperatingSystem
                        },
                        onOpenApplicationManager: {
                            pushDetailPane(.applicationManager)
                            Task {
                                await viewModel.loadApplicationsForSelectedDevice()
                            }
                        },
                        onOpenCertificateManager: {
                            pushDetailPane(.certificateManager)
                        },
                        onOpenAccountManager: {
                            pushDetailPane(.accountManager)
                        },
                        onOpenConfigurationProfileManager: {
                            pushDetailPane(.configurationProfileManager)
                        },
                        onOpenGroupMembershipManager: {
                            pushDetailPane(.groupMembershipManager)
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "stethoscope",
                        description: "Select a device in Results before opening diagnostics.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .certificateManager:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportCertificateManagerView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        onGoBack: {
                            popDetailPane()
                        },
                        onRenewMDMProfile: {
                            Task {
                                await viewModel.renewMDMProfileForSelectedDevice()
                            }
                        },
                        onAddCertificate: { certificateName, profileIdentifier in
                            Task {
                                await viewModel.addCertificate(
                                    certificateName: certificateName,
                                    profileIdentifier: profileIdentifier
                                )
                            }
                        },
                        onRemoveCertificate: { certificate in
                            Task {
                                await viewModel.removeCertificate(certificate)
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "checkmark.seal",
                        description: "Select a device in Results before opening Certificate Manager.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .accountManager:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportLocalUserControlView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        onGoBack: {
                            popDetailPane()
                        },
                        onAddAccount: { username, fullName, password in
                            Task {
                                await viewModel.addLocalUserAccount(
                                    username: username,
                                    fullName: fullName,
                                    password: password
                                )
                            }
                        },
                        onDeleteAccount: { username in
                            Task {
                                await viewModel.deleteLocalUserAccount(username: username)
                            }
                        },
                        onResetPassword: { accountGUID, newPassword in
                            Task {
                                await viewModel.resetLocalUserPassword(
                                    accountGUID: accountGUID,
                                    newPassword: newPassword
                                )
                            }
                        },
                        onUnlockAccount: { username in
                            Task {
                                await viewModel.unlockLocalUserAccount(username: username)
                            }
                        },
                        onEditAccount: { username, fullName, accountGUID, newPassword in
                            Task {
                                await viewModel.editLocalUserAccount(
                                    username: username,
                                    fullName: fullName,
                                    accountGUID: accountGUID,
                                    newPassword: newPassword
                                )
                            }
                        },
                        onSetPIN: { pin, message, phoneNumber in
                            Task {
                                await viewModel.setMobileDevicePIN(
                                    pin: pin,
                                    message: message,
                                    phoneNumber: phoneNumber
                                )
                            }
                        },
                        onClearPIN: { unlockToken in
                            Task {
                                await viewModel.clearMobileDevicePIN(unlockToken: unlockToken)
                            }
                        },
                        onClearRestrictionsPIN: {
                            Task {
                                await viewModel.clearRestrictionsPIN()
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "person.2",
                        description: "Select a device in Results before opening Account Manager.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .mobilePINControl:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportMobilePINControlView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        onGoBack: {
                            popDetailPane()
                        },
                        onSetPIN: { pin, message, phoneNumber in
                            Task {
                                await viewModel.setMobileDevicePIN(
                                    pin: pin,
                                    message: message,
                                    phoneNumber: phoneNumber
                                )
                            }
                        },
                        onClearPIN: { unlockToken in
                            Task {
                                await viewModel.clearMobileDevicePIN(unlockToken: unlockToken)
                            }
                        },
                        onClearRestrictionsPIN: {
                            Task {
                                await viewModel.clearRestrictionsPIN()
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "lock",
                        description: "Select a device in Results before opening Mobile PIN Control.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .configurationProfileManager:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportConfigurationProfileManagerView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        onGoBack: {
                            popDetailPane()
                        },
                        onReload: {
                            Task {
                                await viewModel.refreshSelectedDeviceDetail()
                            }
                        },
                        onAddProfile: { profileName, profileIdentifier in
                            Task {
                                await viewModel.addConfigurationProfile(
                                    profileName: profileName,
                                    profileIdentifier: profileIdentifier
                                )
                            }
                        },
                        onRemoveProfile: { profile in
                            Task {
                                await viewModel.removeConfigurationProfile(profile)
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "gear.badge.checkmark",
                        description: "Select a device in Results before opening Configuration Profile Manager.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            case .groupMembershipManager:
                if let selectedDetail = viewModel.selectedDetail {
                    SupportGroupMembershipManagerView(
                        detail: selectedDetail,
                        isPerformingAction: viewModel.isPerformingAction,
                        statusMessage: viewModel.statusMessage,
                        errorMessage: viewModel.errorMessage,
                        onGoBack: {
                            popDetailPane()
                        },
                        onReload: {
                            Task {
                                await viewModel.refreshSelectedDeviceDetail()
                            }
                        },
                        onAddMembership: { groupName, groupType in
                            Task {
                                await viewModel.addGroupMembership(
                                    groupName: groupName,
                                    groupType: groupType
                                )
                            }
                        },
                        onRemoveMembership: { group in
                            Task {
                                await viewModel.removeGroupMembership(group)
                            }
                        }
                    )
                } else {
                    SupportUnavailablePaneView(
                        title: "Select a Device",
                        systemImage: "person.3.sequence",
                        description: "Select a device in Results before opening Group Membership Manager.",
                        onGoBack: {
                            popDetailPane()
                        }
                    )
                }
            }
        }
        .task {
            await viewModel.bootstrap()
        }
        .onChange(of: viewModel.selectedResultID) { _, _ in
            Task {
                await viewModel.loadSelectedDeviceDetail()
            }
        }
        .alert(
            pendingConfirmationAction?.confirmationTitle ?? "Confirm",
            isPresented: Binding(
                get: { pendingConfirmationAction != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingConfirmationAction = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingConfirmationAction = nil
            }

            Button("Confirm", role: pendingConfirmationAction?.requiresConfirmation == true ? .destructive : nil) {
                guard let action = pendingConfirmationAction else {
                    return
                }

                pendingConfirmationAction = nil

                if action == .eraseDevice || action == .removeManagementProfile {
                    typedRemovalConfirmationText = ""
                    pendingTypedRemovalAction = action
                    return
                }

                Task {
                    await viewModel.performAction(action)
                }
            }
        } message: {
            Text(pendingConfirmationAction?.confirmationMessage ?? "")
        }
        .sheet(item: $pendingTypedRemovalAction) { action in
            SupportTypedRemovalConfirmationSheet(
                action: action,
                confirmationText: $typedRemovalConfirmationText,
                onCancel: {
                    pendingTypedRemovalAction = nil
                    typedRemovalConfirmationText = ""
                },
                onConfirm: {
                    pendingTypedRemovalAction = nil
                    typedRemovalConfirmationText = ""
                    Task {
                        await viewModel.performAction(action)
                    }
                }
            )
        }
        .dynamicTypeSize(.xLarge)
    }

    /// Handles pushDetailPane.
    private func pushDetailPane(_ pane: SupportTechnicianDetailPane) {
        if detailPane == pane {
            return
        }

        detailPaneHistory.append(pane)
    }

    /// Handles popDetailPane.
    private func popDetailPane() {
        guard detailPaneHistory.count > 1 else {
            return
        }

        _ = detailPaneHistory.popLast()
    }
}

/// SupportUnavailablePaneView declaration.
private struct SupportUnavailablePaneView: View {
    let title: String
    let systemImage: String
    let description: String
    let onGoBack: (() -> Void)?

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if let onGoBack {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button {
                        onGoBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }
}

/// SupportTicketListView declaration.
private struct SupportTicketListView: View {
    let tickets: [TechnicianTicketRecord]
    let activeTicketID: UUID?
    let selectedTicketID: UUID?
    let onGoBack: () -> Void
    let onSelectTicket: (UUID) -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onGoBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.appSecondary)
            }

            Section {
                if tickets.isEmpty {
                    Text("No saved tickets yet. Use Start Log from the control column to create one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tickets) { ticket in
                        Button {
                            onSelectTicket(ticket.id)
                        } label: {
                            SupportTicketRow(
                                ticket: ticket,
                                isActive: ticket.id == activeTicketID,
                                isSelected: ticket.id == selectedTicketID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Saved Tickets")
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Tickets")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
    }
}

/// SupportTicketRow declaration.
private struct SupportTicketRow: View {
    let ticket: TechnicianTicketRecord
    let isActive: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(ticket.reference)
                    .font(.headline)

                if isActive {
                    Text("Logging")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BrandColors.greenPrimary)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BrandColors.greenPrimary)
                }
            }

            Text("Updated: \(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Entries: \(ticket.entryCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// SupportTicketEditorView declaration.
private struct SupportTicketEditorView: View {
    let ticketDetail: TechnicianTicketDetailRecord?
    @Binding var ticketEditorNotes: String
    @Binding var ticketEditorNoteDraft: String
    let onGoBack: () -> Void
    let onInitiateLoggedSession: () -> Void
    let onResumeLoggedSession: () -> Void
    let onSaveForLater: () -> Void
    let onSaveNotes: () -> Void
    let onAddNote: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    onGoBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.appSecondary)
            }

            if let ticketDetail {
                Section("Ticket") {
                    SupportFieldRow(key: "Ticket", value: ticketDetail.ticket.reference)
                    SupportFieldRow(key: "Created", value: ticketDetail.ticket.createdAt.formatted(date: .abbreviated, time: .shortened))
                    SupportFieldRow(key: "Updated", value: ticketDetail.ticket.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    SupportFieldRow(key: "Entries", value: String(ticketDetail.ticket.entryCount))

                    if ticketDetail.ticket.isActiveSession {
                        Label("Logging is currently active for this ticket.", systemImage: "record.circle")
                            .foregroundStyle(BrandColors.greenPrimary)
                            .font(.footnote.weight(.semibold))
                    }
                }

                Section("Workflow") {
                    Button {
                        onInitiateLoggedSession()
                    } label: {
                        Label("Initiate Logged Session", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                    Button {
                        onSaveForLater()
                    } label: {
                        Label("Save for Later", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                    Button {
                        onResumeLoggedSession()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                }

                Section("Ticket Notes") {
                    TextEditor(text: $ticketEditorNotes)
                        .frame(minHeight: 120)

                    Button {
                        onSaveNotes()
                    } label: {
                        Label("Save Notes", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                }

                Section("Add Log Note") {
                    TextField("Add note to the ticket log", text: $ticketEditorNoteDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        onAddNote()
                    } label: {
                        Label("Add Note", systemImage: "plus.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                }

                Section("Log Entries") {
                    if ticketDetail.entries.isEmpty {
                        Text("No log entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ticketDetail.entries) { entry in
                            SupportTicketLogEntryRow(entry: entry)
                        }
                    }
                }
            } else {
                Section {
                    ProgressView("Loading ticket editor...")
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle(ticketDetail?.ticket.reference ?? "Ticket")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
    }
}

/// SupportTicketLogEntryRow declaration.
private struct SupportTicketLogEntryRow: View {
    let entry: TechnicianLogEntryRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(entry.category.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(entry.action)
                .font(.subheadline.weight(.semibold))

            Text(entry.detail)
                .font(.footnote)

            if let metadataJSON = entry.metadataJSON,
               metadataJSON.isEmpty == false
            {
                Text(metadataJSON)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}


/// SupportSearchResultRow declaration.
private struct SupportSearchResultRow: View {
    let result: SupportSearchResult
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BrandTheme.Spacing.compact) {
            HStack(spacing: 8) {
                Image(systemName: result.assetType.iconSystemName)
                    .foregroundStyle(.tint)
                    .frame(width: 22)

                Text(result.displayName)
                    .font(BrandSearchResultTypography.headline())

                Spacer(minLength: 0)

                Text(result.assetType.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(BrandTheme.groupedSurface)
                    .clipShape(Capsule())

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BrandColors.greenPrimary)
                }
            }

            Text("Serial: \(result.serialNumber)")
                .font(BrandSearchResultTypography.subheadline())

            if let username = result.username,
               username.isEmpty == false
            {
                Text("User: \(username)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let model = result.model,
               model.isEmpty == false
            {
                Text("Model: \(model)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let osVersion = result.osVersion,
               osVersion.isEmpty == false
            {
                Text("OS: \(osVersion)")
                    .font(BrandSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// SupportDeviceDetailView declaration.
private struct SupportDeviceDetailView: View {
    let detail: SupportDeviceDetail
    let actions: [SupportManagementAction]
    let availableApplications: [SupportManagedApplication]
    let isLoadingDetail: Bool
    let isPerformingAction: Bool
    let isLoadingApplications: Bool
    let isPerformingApplicationCommand: Bool
    let actionResult: SupportActionResult?
    let statusMessage: String?
    let errorMessage: String?
    let canGoBack: Bool
    let onGoBack: () -> Void
    let onRefresh: () -> Void
    let onAction: (SupportManagementAction) -> Void
    let onOpenApplicationManager: () -> Void
    let onOpenDiagnosticView: () -> Void
    let onOpenCertificateManager: () -> Void
    let onOpenAccountManager: () -> Void
    let onOpenMobilePINControl: () -> Void
    let onOpenConfigurationProfileManager: () -> Void
    let onOpenGroupMembershipManager: () -> Void

    @State private var isRawPayloadExpanded = false
    @State private var isRefreshConfirmationPresented = false
    @State private var isUnlockTokenRevealed = false

    private var canSendOperatingSystemUpdate: Bool {
        actions.contains(.updateOperatingSystem)
    }

    private var mobileUnlockToken: String? {
        guard detail.summary.assetType == .mobileDevice else {
            return nil
        }

        for section in detail.sections {
            for item in section.items {
                let normalized = normalizedFieldToken("\(section.title) \(item.key)")
                if normalized.contains("unlocktoken") {
                    return item.value
                }
            }
        }

        return nil
    }

    private var prioritizedSections: [SupportDetailSection] {
        detail.sections
            .filter { shouldIncludeDefaultSection($0.title) }
            .sorted { lhs, rhs in
                let lhsPriority = sectionPriority(for: lhs.title)
                let rhsPriority = sectionPriority(for: rhs.title)
                if lhsPriority == rhsPriority {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhsPriority < rhsPriority
            }
    }

    private func normalizedSectionKey(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func shouldIncludeDefaultSection(_ sectionTitle: String) -> Bool {
        let normalized = normalizedSectionKey(sectionTitle)
        let excludedFragments = [
            "localuseraccount",
            "localuseraccounts",
            "groupmembership",
            "groupmemberships",
            "certificate",
            "certificates",
            "beacon",
            "beacons",
            "licensedsoftware",
            "packagereceipt",
            "packagereceipts"
        ]

        return excludedFragments.contains(where: { normalized.contains($0) }) == false
    }

    private func isConfigurationProfilesSection(_ sectionTitle: String) -> Bool {
        let normalized = normalizedSectionKey(sectionTitle)
        return normalized.contains("configurationprofile")
    }

    var body: some View {
        List {
            Section {
                SupportFieldRow(key: "Device Type", value: detail.summary.assetType.title)
                SupportFieldRow(key: "Device Name", value: detail.summary.displayName)
                SupportFieldRow(key: "Serial Number", value: detail.summary.serialNumber)
                SupportFieldRow(key: "Inventory ID", value: detail.summary.inventoryID)

                if let username = detail.summary.username,
                   username.isEmpty == false
                {
                    SupportFieldRow(key: "Assigned User", value: username)
                }

                if let email = detail.summary.email,
                   email.isEmpty == false
                {
                    SupportFieldRow(key: "User Email", value: email)
                }

                if let model = detail.summary.model,
                   model.isEmpty == false
                {
                    SupportFieldRow(key: "Model", value: model)
                }

                if let osVersion = detail.summary.osVersion,
                   osVersion.isEmpty == false
                {
                    if detail.summary.assetType == .mobileDevice {
                        VStack(alignment: .leading, spacing: 8) {
                            SupportFieldRow(key: "Operating System", value: osVersion)

                            HStack(spacing: 10) {
                                Button {
                                    onAction(.updateOperatingSystem)
                                } label: {
                                    Label("Update iOS", systemImage: "square.and.arrow.down.on.square")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.appSecondary)
                                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                                .disabled(isLoadingDetail || isPerformingAction || canSendOperatingSystemUpdate == false)

                                SupportInfoButton(
                                    title: "Update iOS",
                                    helpText: "Queues a managed iOS update plan for this mobile device."
                                )
                            }
                        }
                    } else {
                        SupportFieldRow(key: "Operating System", value: osVersion)
                    }
                }

                if let lastInventoryUpdate = detail.summary.lastInventoryUpdate,
                   lastInventoryUpdate.isEmpty == false
                {
                    SupportFieldRow(key: "Last Inventory Update", value: lastInventoryUpdate)
                }

                if let managementID = detail.summary.managementID,
                   managementID.isEmpty == false
                {
                    SupportFieldRow(key: "Management ID", value: managementID)
                }

                if let clientManagementID = detail.summary.clientManagementID,
                   clientManagementID.isEmpty == false
                {
                    SupportFieldRow(key: "Client Management ID", value: clientManagementID)
                }

                if detail.summary.assetType == .mobileDevice {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                isUnlockTokenRevealed.toggle()
                            } label: {
                                Label("Unlock Token", systemImage: "key")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.appSecondary)
                            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                            SupportInfoButton(
                                title: "Unlock Token",
                                helpText: "Reveals unlock token details, when available in inventory payload, and provides one-click copy."
                            )
                        }

                        if isUnlockTokenRevealed {
                            if let mobileUnlockToken,
                               mobileUnlockToken.isEmpty == false
                            {
                                Text(mobileUnlockToken)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 10) {
                                    Button {
                                        BrandClipboard.copy(mobileUnlockToken)
                                    } label: {
                                        Label("Copy Unlock Token", systemImage: "doc.on.doc")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.appSecondary)
                                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                                    SupportInfoButton(
                                        title: "Copy Unlock Token",
                                        helpText: "Copies the revealed unlock token to clipboard."
                                    )
                                }
                            } else {
                                Text("No unlock token was returned in the current mobile inventory payload.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        isRefreshConfirmationPresented = true
                    } label: {
                        Label("Refresh Device Data", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction)

                    SupportInfoButton(
                        title: "Refresh Device Data",
                        helpText: "Reloads the selected device data from Jamf Pro, including diagnostics and available actions."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Summary",
                    helpText: "Highest-priority identity and ownership fields for the selected device."
                )
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        onAction(.updateOperatingSystem)
                    } label: {
                        Label("Update iOS/macOS", systemImage: "square.and.arrow.down.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction || canSendOperatingSystemUpdate == false)

                    SupportInfoButton(
                        title: "Update iOS/macOS",
                        helpText: "Sends an iOS/macOS managed OS update plan to the selected device."
                    )
                }

                if canSendOperatingSystemUpdate == false {
                    Text("Update iOS/macOS is unavailable for this target until Jamf management identifiers are present.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SupportSectionHeader(
                    title: "OS Update",
                    helpText: "Queues the managed iOS/macOS update command for the selected device."
                )
            }

            Section {
                ForEach(detail.diagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: diagnostic.severity.iconSystemName)
                            .foregroundStyle(color(for: diagnostic.severity))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(diagnostic.title)
                                .font(.body.weight(.semibold))
                            Text(diagnostic.value)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenDiagnosticView()
                    } label: {
                        Label("Diagnostic View", systemImage: "stethoscope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction)

                    SupportInfoButton(
                        title: "Diagnostics",
                        helpText: "Opens an expanded diagnostics dashboard with system metrics, indicators, and visual charts for the selected device."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Diagnostics",
                    helpText: "Operational health checks, security posture, and inventory staleness indicators."
                )
            }

            Section {
                Button {
                    onOpenApplicationManager()
                } label: {
                    HStack(spacing: 10) {
                        Label("Application Manager", systemImage: "app.badge")
                            .font(.body.weight(.semibold))
                        Spacer(minLength: 0)
                        Text("\(availableApplications.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BrandTheme.groupedSurface)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.appSecondary)
                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                .disabled(isLoadingApplications || isPerformingApplicationCommand || isLoadingDetail)

                if isLoadingApplications {
                    ProgressView("Loading available applications...")
                        .font(.footnote)
                } else if availableApplications.isEmpty {
                    Text("No cached app catalog yet. Open Application Manager to load available apps from Jamf Pro.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SupportSectionHeader(
                    title: "Application Manager",
                    helpText: "Open a dedicated app manager to select an app and perform install, update, reinstall, or remove actions."
                )
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        onOpenAccountManager()
                    } label: {
                        HStack {
                            Label("Account Manager", systemImage: "person.2")
                            Spacer(minLength: 0)
                            Text("\(detail.localUserAccounts.count)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BrandTheme.groupedSurface)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction)

                    SupportInfoButton(
                        title: "Account Manager",
                        helpText: "Opens account controls to add, remove, edit local users, and reset passwords/PINs."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Account Manager",
                    helpText: "Account manager replaces local-user account details in the default device view."
                )
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        onOpenCertificateManager()
                    } label: {
                        HStack {
                            Label("Certificate Manager", systemImage: "checkmark.seal")
                            Spacer(minLength: 0)
                            Text("\(detail.certificates.count)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BrandTheme.groupedSurface)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction)

                    SupportInfoButton(
                        title: "Certificate Manager",
                        helpText: "Opens the certificate manager with installed certificate inventory and management controls."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Certificate Manager",
                    helpText: "Certificate manager replaces certificate details in the default device view."
                )
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        onOpenGroupMembershipManager()
                    } label: {
                        HStack {
                            Label("Group Membership Manager", systemImage: "person.3.sequence")
                            Spacer(minLength: 0)
                            Text("\(detail.groupMemberships.count)")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(BrandTheme.groupedSurface)
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingDetail || isPerformingAction)

                    SupportInfoButton(
                        title: "Group Membership Manager",
                        helpText: "Opens group membership manager controls. This replaces group-membership details in the default view."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Group Membership Manager",
                    helpText: "Manage group memberships from a dedicated manager view."
                )
            }

            if detail.summary.assetType == .mobileDevice {
                Section {
                    HStack(spacing: 10) {
                        Button {
                            onOpenMobilePINControl()
                        } label: {
                            Label("Control", systemImage: "lock")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appSecondary)
                        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                        .disabled(isLoadingDetail || isPerformingAction)

                        SupportInfoButton(
                            title: "Mobile Device PIN Control",
                            helpText: "Opens controls to clear, reset, or change mobile passcode/PIN commands."
                        )
                    }
                } header: {
                    SupportSectionHeader(
                        title: "Mobile Device PIN",
                        helpText: "Open passcode controls for mobile device PIN operations."
                    )
                }
            }

            Section {
                if isPerformingAction {
                    ProgressView("Submitting Jamf command...")
                }

                ForEach(actions) { action in
                    HStack(spacing: 10) {
                        managementActionButton(for: action)

                        SupportInfoButton(
                            title: action.title,
                            helpText: actionHelpText(for: action)
                        )
                    }
                }
            } header: {
                SupportSectionHeader(
                    title: "Management",
                    helpText: "Remote commands and sensitive retrieval actions. Destructive actions require confirmation."
                )
            }

            if let actionResult {
                Section {
                    SupportFieldRow(key: "Action", value: actionResult.title)

                    Text(actionResult.detail)
                        .font(.body)

                    if let sensitiveValue = actionResult.sensitiveValue {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sensitiveValue)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)

                            HStack(spacing: 10) {
                                Button {
                                    BrandClipboard.copy(sensitiveValue)
                                } label: {
                                    Label("Copy Value", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.appSecondary)
                                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                                SupportInfoButton(
                                    title: "Copy Value",
                                    helpText: "Copies the secret value to your clipboard for secure handoff workflows."
                                )
                            }
                        }
                    }
                } header: {
                    SupportSectionHeader(
                        title: "Last Action",
                        helpText: "Most recent action response from Jamf Pro for this device."
                    )
                }
            }

            ForEach(prioritizedSections) { section in
                Section {
                    if isConfigurationProfilesSection(section.title) {
                        HStack(spacing: 10) {
                            Button {
                                onOpenConfigurationProfileManager()
                            } label: {
                                HStack {
                                    Label("Configuration Profile Manager", systemImage: "gear.badge.checkmark")
                                    Spacer(minLength: 0)
                                    Text("\(detail.configurationProfiles.count)")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(BrandTheme.groupedSurface)
                                        .clipShape(Capsule())
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.appSecondary)
                            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                            .disabled(isLoadingDetail || isPerformingAction)

                            SupportInfoButton(
                                title: "Configuration Profile Manager",
                                helpText: "Opens profile manager controls without removing ConfigurationProfiles data from this default view."
                            )
                        }
                    }

                    ForEach(section.items) { item in
                        if shouldDisplayFieldItem(item, in: section) {
                            SupportFieldRow(key: item.key, value: item.value)
                        }
                    }
                } header: {
                    SupportSectionHeader(
                        title: section.title,
                        helpText: helpText(for: section.title)
                    )
                }
            }

            Section {
                DisclosureGroup("Show JSON", isExpanded: $isRawPayloadExpanded) {
                    ScrollView(.horizontal) {
                        Text(detail.rawJSON)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
            } header: {
                SupportSectionHeader(
                    title: "Raw Payload",
                    helpText: "Full Jamf Pro response for troubleshooting when normalized fields do not contain the needed data."
                )
            }
        }
        .appInsetGroupedListStyle()
        .environment(\.defaultMinListRowHeight, 44)
        .supportDetailBackChevron(onGoBack: onGoBack, isEnabled: canGoBack)
        .alert("Refresh Device Data?", isPresented: $isRefreshConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onRefresh()
            }
        } message: {
            Text("Reload device summary, diagnostics, and manager data from Jamf Pro.")
        }
    }

    @ViewBuilder
    private func managementActionButton(for action: SupportManagementAction) -> some View {
        if action == .eraseDevice {
            Button {
                onAction(action)
            } label: {
                managementActionLabel(for: action)
            }
            .buttonStyle(.appDanger)
            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
            .disabled(isPerformingAction || isLoadingDetail)
        } else {
            Button {
                onAction(action)
            } label: {
                managementActionLabel(for: action)
            }
            .buttonStyle(.appSecondary)
            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
            .disabled(isPerformingAction || isLoadingDetail)
        }
    }

    private func color(for severity: SupportDiagnosticSeverity) -> Color {
        switch severity {
        case .info:
            return BrandColors.greenPrimary
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func sectionPriority(for title: String) -> Int {
        let value = title.lowercased()
        if value.contains("general") || value.contains("summary") {
            return 0
        }
        if value.contains("user") || value.contains("location") {
            return 1
        }
        if value.contains("operating system") || value.contains("os") {
            return 2
        }
        if value.contains("hardware") || value.contains("model") {
            return 3
        }
        if value.contains("security") || value.contains("encryption") || value.contains("filevault") {
            return 4
        }
        if value.contains("network") {
            return 5
        }
        if value.contains("disk") || value.contains("storage") {
            return 6
        }
        if value.contains("application") {
            return 7
        }

        return 20
    }

    /// Handles helpText.
    private func helpText(for sectionTitle: String) -> String {
        let value = sectionTitle.lowercased()
        if value.contains("general") {
            return "Core inventory identifiers and device profile values from Jamf Pro."
        }
        if value.contains("user") || value.contains("location") {
            return "Ownership and assignment details used for technician routing and outreach."
        }
        if value.contains("operating system") {
            return "OS version and update posture used to validate compliance and supportability."
        }
        if value.contains("hardware") {
            return "Model and platform characteristics used during triage and replacement planning."
        }
        if value.contains("security") || value.contains("encryption") {
            return "Security controls and encryption state relevant for policy enforcement."
        }
        if value.contains("application") {
            return "Installed software data used for compatibility and incident investigations."
        }
        if value.contains("network") {
            return "Network addressing and connectivity indicators reported by inventory."
        }

        return "Additional inventory data returned by Jamf Pro for deep troubleshooting."
    }

    /// Handles actionHelpText.
    private func actionHelpText(for action: SupportManagementAction) -> String {
        switch action {
        case .refreshInventory:
            return "Queues an MDM inventory update so Jamf reports current device state."
        case .updateOperatingSystem:
            return "Sends a Jamf managed software update plan targeting this specific device."
        case .discoverApplications:
            return "Queues an installed application discovery request for this device."
        case .restartDevice:
            return "Queues a remote restart command for the selected managed device."
        case .removeManagementProfile:
            return "Removes management from the selected device. This can break policy and app delivery workflows."
        case .eraseDevice:
            return "Sends a destructive erase command. Use only for decommission, theft, or security response scenarios."
        case .viewFileVaultPersonalRecoveryKey:
            return "Retrieves the FileVault personal recovery key from Jamf Pro for approved recovery workflows."
        case .viewRecoveryLockPassword:
            return "Retrieves the macOS recovery lock password reported by Jamf Pro."
        case .viewDeviceLockPIN:
            return "Retrieves the stored device lock PIN from Jamf Pro."
        case .viewLAPSAccountPassword:
            return "Retrieves the current LAPS-managed local admin password from Jamf Pro."
        case .rotateLAPSPassword:
            return "Requests rotation of the LAPS-managed local admin password for this device."
        }
    }

    /// Handles normalizedFieldToken.
    private func normalizedFieldToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    /// Handles shouldDisplayFieldItem.
    private func shouldDisplayFieldItem(_ item: SupportDetailItem, in section: SupportDetailSection) -> Bool {
        let normalized = normalizedFieldToken("\(section.title) \(item.key)")
        if detail.summary.assetType == .mobileDevice,
           normalized.contains("unlocktoken")
        {
            return false
        }

        return true
    }

    /// Handles managementActionLabel.
    private func managementActionLabel(for action: SupportManagementAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body.weight(.semibold))

                Text(action.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// SupportApplicationManagerView declaration.
private struct SupportApplicationManagerView: View {
    private enum CatalogAction: String {
        case reload
        case discover
        case updateOperatingSystem

        var title: String {
            switch self {
            case .reload:
                return "Reload App Catalog?"
            case .discover:
                return "Discover Applications?"
            case .updateOperatingSystem:
                return "Update iOS/macOS?"
            }
        }

        var message: String {
            switch self {
            case .reload:
                return "Refresh app catalog data from Jamf Pro for this device."
            case .discover:
                return "Queue installed application discovery for this device."
            case .updateOperatingSystem:
                return "Send a managed OS update plan to this device."
            }
        }
    }

    let deviceName: String
    let applications: [SupportManagedApplication]
    let isLoadingApplications: Bool
    let isPerformingCommand: Bool
    let isPerformingManagementAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let commandProvider: (SupportManagedApplication) -> [SupportApplicationCommand]
    let onGoBack: () -> Void
    let onReload: () -> Void
    let onDiscoverApplications: () -> Void
    let onUpdateOperatingSystem: () -> Void
    let onCommand: (SupportApplicationCommand, SupportManagedApplication) -> Void

    @State private var selectedApplicationID: String?
    @State private var pendingCommand: SupportApplicationCommand?
    @State private var pendingApplication: SupportManagedApplication?
    @State private var pendingCatalogAction: CatalogAction?

    private var selectedApplication: SupportManagedApplication? {
        applications.first(where: { $0.id == selectedApplicationID })
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        pendingCatalogAction = .reload
                    } label: {
                        Label("Reload App Catalog", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isLoadingApplications || isPerformingCommand)

                    SupportInfoButton(
                        title: "Reload App Catalog",
                        helpText: "Refreshes the list of available apps for this device from Jamf Pro."
                    )
                }

                if isLoadingApplications {
                    ProgressView("Loading applications from Jamf Pro...")
                        .font(.footnote)
                }

                HStack(spacing: 10) {
                    Button {
                        pendingCatalogAction = .discover
                    } label: {
                        Label("Discover Applications", systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingManagementAction || isLoadingApplications)

                    SupportInfoButton(
                        title: "Discover Applications",
                        helpText: "Queues installed application discovery for the selected device, then refreshes the app catalog."
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        pendingCatalogAction = .updateOperatingSystem
                    } label: {
                        Label("Update iOS/macOS", systemImage: "square.and.arrow.down.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingManagementAction || isLoadingApplications)

                    SupportInfoButton(
                        title: "Update iOS/macOS",
                        helpText: "Sends a managed software update plan targeting this iOS/macOS device."
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SupportSectionHeader(
                    title: "Application Catalog",
                    helpText: "Load and review apps available to this device in Jamf Pro."
                )
            }

            Section {
                if applications.isEmpty {
                    Text("No applications loaded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(applications) { application in
                        Button {
                            selectedApplicationID = application.id
                        } label: {
                            SupportApplicationRow(
                                application: application,
                                isSelected: selectedApplicationID == application.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                SupportSectionHeader(
                    title: "Available Apps",
                    helpText: "Select an app to open command options."
                )
            }

            Section {
                if let selectedApplication {
                    let commands = commandProvider(selectedApplication)
                    let commandSet = Set(commands)

                    VStack(spacing: 10) {
                        actionButton(
                            command: .install,
                            label: "Add / Install",
                            isEnabled: commandSet.contains(.install),
                            selectedApplication: selectedApplication
                        )
                        actionButton(
                            command: .update,
                            label: "Update",
                            isEnabled: commandSet.contains(.update),
                            selectedApplication: selectedApplication
                        )
                        actionButton(
                            command: .reinstall,
                            label: "Reinstall",
                            isEnabled: commandSet.contains(.reinstall),
                            selectedApplication: selectedApplication
                        )
                        actionButton(
                            command: .remove,
                            label: "Uninstall / Remove",
                            isEnabled: commandSet.contains(.remove),
                            selectedApplication: selectedApplication
                        )
                    }
                } else {
                    Text("Select an application above to enable add/install, update, reinstall, and uninstall/remove actions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SupportSectionHeader(
                    title: "App Actions",
                    helpText: "Run the selected app action against the current device."
                )
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Application Manager")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert(
            pendingCommand?.confirmationTitle ?? "Confirm",
            isPresented: Binding(
                get: { pendingCommand != nil && pendingApplication != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingCommand = nil
                        pendingApplication = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingCommand = nil
                pendingApplication = nil
            }

            Button("Confirm", role: pendingCommand == .remove ? .destructive : nil) {
                guard let pendingCommand,
                      let pendingApplication
                else {
                    return
                }

                onCommand(pendingCommand, pendingApplication)
                self.pendingCommand = nil
                self.pendingApplication = nil
            }
        } message: {
            Text(pendingCommand?.confirmationMessage ?? "")
        }
        .alert(
            pendingCatalogAction?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingCatalogAction != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingCatalogAction = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingCatalogAction = nil
            }

            Button("Confirm") {
                guard let pendingCatalogAction else {
                    return
                }

                switch pendingCatalogAction {
                case .reload:
                    onReload()
                case .discover:
                    onDiscoverApplications()
                case .updateOperatingSystem:
                    onUpdateOperatingSystem()
                }

                self.pendingCatalogAction = nil
            }
        } message: {
            Text(pendingCatalogAction?.message ?? "")
        }
        .onAppear {
            if isLoadingApplications == false {
                onReload()
            }
        }
    }

    /// Handles actionButton.
    @ViewBuilder
    private func actionButton(
        command: SupportApplicationCommand,
        label: String,
        isEnabled: Bool,
        selectedApplication: SupportManagedApplication
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                pendingCommand = command
                pendingApplication = selectedApplication
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: command.systemImage)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.body.weight(.semibold))
                        Text(command.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.appSecondary)
            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
            .disabled(isEnabled == false || isPerformingCommand || isPerformingManagementAction || isLoadingApplications)

            SupportInfoButton(
                title: label,
                helpText: appCommandHelpText(command)
            )
        }
    }

    /// Handles appCommandHelpText.
    private func appCommandHelpText(_ command: SupportApplicationCommand) -> String {
        switch command {
        case .install:
            return "Installs or deploys the selected app to the current device via Jamf Pro."
        case .update:
            return "Requests Jamf Pro to update the selected app on the current device."
        case .reinstall:
            return "Reinstalls the selected app to repair missing or damaged app components."
        case .remove:
            return "Removes the selected app from the device. This action requires confirmation."
        }
    }
}

/// SupportApplicationRow declaration.
private struct SupportApplicationRow: View {
    let application: SupportManagedApplication
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "app.fill")
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.displayName)
                    .font(.body.weight(.semibold))

                if let bundleIdentifier = application.bundleIdentifier,
                   bundleIdentifier.isEmpty == false
                {
                    Text(bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Text(application.isInstalled ? "Installed" : "Available")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(application.isInstalled ? BrandColors.greenPrimary.opacity(0.15) : BrandTheme.groupedSurface)
                        .clipShape(Capsule())

                    if let appVersion = application.appVersion,
                       appVersion.isEmpty == false
                    {
                        Text("v\(appVersion)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(application.source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandColors.greenPrimary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// SupportDeviceDiagnosticsView declaration.
private struct SupportDeviceDiagnosticsView: View {
    private struct Metric: Identifiable {
        let id: String
        let title: String
        let value: Double
        let color: Color
    }

    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let latestDeviceLogs: String?
    let onGoBack: () -> Void
    let onRefreshDiagnostics: () -> Void
    let onRequestErrorLogs: () -> Void
    let onUpdateOperatingSystem: () -> Void
    let onOpenApplicationManager: () -> Void
    let onOpenCertificateManager: () -> Void
    let onOpenAccountManager: () -> Void
    let onOpenConfigurationProfileManager: () -> Void
    let onOpenGroupMembershipManager: () -> Void

    @State private var isRawJSONExpanded = false
    @State private var isGatherConfirmationPresented = false
    @State private var isErrorLogsExpanded = false
    @State private var isGetLogsConfirmationPresented = false
    @State private var isServicesDetailPresented = false

    private var flattenedValues: [String: String] {
        var output: [String: String] = [:]
        for section in detail.sections {
            for item in section.items {
                output["\(section.title).\(item.key)"] = item.value
                if output[item.key] == nil {
                    output[item.key] = item.value
                }
            }
        }
        return output
    }

    private var storageUsedPercent: Double? {
        if let direct = numericValue(matching: ["usedspacepercentage"]) {
            return clampPercent(direct)
        }
        if let direct = numericValue(matching: ["percentageused"]) {
            return clampPercent(direct)
        }
        if let used = numericValue(matching: ["usedspacemb"]),
           let capacity = numericValue(matching: ["capacitymb"]),
           capacity > 0
        {
            return clampPercent((used / capacity) * 100)
        }
        if let available = numericValue(matching: ["availablespacemb"]),
           let capacity = numericValue(matching: ["capacitymb"]),
           capacity > 0
        {
            return clampPercent(((capacity - available) / capacity) * 100)
        }

        return nil
    }

    private var storageCapacityMB: Double? {
        numericValue(matching: ["capacitymb", "storagecapacitymb", "disksize", "totalspacemb"])
    }

    private var storageAvailableMB: Double? {
        numericValue(matching: ["availablespacemb", "freespacemb", "remainingstorage"])
    }

    private var storageUsedMB: Double? {
        if let used = numericValue(matching: ["usedspacemb", "usedstoragemb"]) {
            return used
        }
        if let capacity = storageCapacityMB,
           let available = storageAvailableMB
        {
            return max(capacity - available, 0)
        }

        return nil
    }

    private var batteryLevelPercent: Double? {
        if let value = numericValue(matching: ["batterylevel"]) {
            return clampPercent(value)
        }
        return nil
    }

    private var memoryUsedPercent: Double? {
        if let direct = numericValue(matching: ["memoryusedpercentage"]) {
            return clampPercent(direct)
        }
        if let used = numericValue(matching: ["usedmemorymb"]),
           let total = numericValue(matching: ["totalmemorymb"]),
           total > 0
        {
            return clampPercent((used / total) * 100)
        }
        if let totalRAM = numericValue(matching: ["totalrammb"]),
           let availableRAM = numericValue(matching: ["availablerammb"]),
           totalRAM > 0
        {
            return clampPercent(((totalRAM - availableRAM) / totalRAM) * 100)
        }

        return nil
    }

    private var memoryTotalMB: Double? {
        numericValue(matching: ["totalmemorymb", "totalrammb", "memorytotalmb"])
    }

    private var memoryAvailableMB: Double? {
        numericValue(matching: ["availablerammb", "availablememorymb", "freerammb"])
    }

    private var memoryUsedMB: Double? {
        if let used = numericValue(matching: ["usedmemorymb", "memoryusedmb"]) {
            return used
        }
        if let total = memoryTotalMB,
           let available = memoryAvailableMB
        {
            return max(total - available, 0)
        }

        return nil
    }

    private var cpuIndicatorPercent: Double? {
        if let direct = numericValue(matching: ["cpuusage"]) {
            return clampPercent(direct)
        }
        if let direct = numericValue(matching: ["processorusage"]) {
            return clampPercent(direct)
        }
        if let clockMHz = numericValue(matching: ["processorspeedmhz"]) {
            // Normalize common clock range into an indicator.
            return clampPercent((clockMHz / 5000) * 100)
        }

        return nil
    }

    private var uptimeHours: Double? {
        if let hours = numericValue(matching: ["uptimehours"]) {
            return max(hours, 0)
        }
        if let seconds = numericValue(matching: ["uptimeseconds", "upTimeInSeconds", "uptimeinseconds"]) {
            return max(seconds / 3600, 0)
        }
        if let minutes = numericValue(matching: ["uptimeminutes", "upTimeInMinutes"]) {
            return max(minutes / 60, 0)
        }

        return nil
    }

    private var osDisplayValue: String {
        if let value = detail.summary.osVersion,
           value.isEmpty == false
        {
            return value
        }

        return "Unknown"
    }

    private var filteredSectionsForDiagnostics: [SupportDetailSection] {
        detail.sections.filter { section in
            let normalized = normalizeSectionTitle(section.title)
            if normalized.contains("packagereceipt") ||
                normalized.contains("packagereceipts")
            {
                return false
            }

            if normalized.contains("certificate") ||
                normalized.contains("localuseraccount") ||
                normalized.contains("groupmembership") ||
                normalized.contains("configurationprofile") ||
                normalized.contains("application")
            {
                return false
            }

            return true
        }
    }

    private var hasServicesSection: Bool {
        detail.sections.contains { section in
            normalizeSectionTitle(section.title).contains("service")
        }
    }

    private var serviceSections: [SupportDetailSection] {
        detail.sections.filter { section in
            normalizeSectionTitle(section.title).contains("service")
        }
    }

    private var metrics: [Metric] {
        var output: [Metric] = []

        if let storageUsedPercent {
            output.append(
                Metric(
                    id: "storage",
                    title: "Storage Used",
                    value: storageUsedPercent,
                    color: .orange
                )
            )
        }

        if let memoryUsedPercent {
            output.append(
                Metric(
                    id: "memory",
                    title: "Memory Used",
                    value: memoryUsedPercent,
                    color: .blue
                )
            )
        }

        if let cpuIndicatorPercent {
            output.append(
                Metric(
                    id: "cpu",
                    title: "CPU Indicator",
                    value: cpuIndicatorPercent,
                    color: .red
                )
            )
        }

        if let batteryLevelPercent {
            output.append(
                Metric(
                    id: "battery",
                    title: "Battery",
                    value: batteryLevelPercent,
                    color: .green
                )
            )
        }

        return output
    }

    private var severityMetrics: [SupportSeverityBarChartView.Metric] {
        let infoCount = detail.diagnostics.filter { $0.severity == .info }.count
        let warningCount = detail.diagnostics.filter { $0.severity == .warning }.count
        let criticalCount = detail.diagnostics.filter { $0.severity == .critical }.count

        return [
            SupportSeverityBarChartView.Metric(id: "info", label: "Info", count: infoCount, color: .green),
            SupportSeverityBarChartView.Metric(id: "warning", label: "Warning", count: warningCount, color: .orange),
            SupportSeverityBarChartView.Metric(id: "critical", label: "Critical", count: criticalCount, color: .red)
        ]
    }

    private var healthScore: Double {
        let warningCount = Double(detail.diagnostics.filter { $0.severity == .warning }.count)
        let criticalCount = Double(detail.diagnostics.filter { $0.severity == .critical }.count)
        let total = Double(max(detail.diagnostics.count, 1))

        let warningPenalty = (warningCount / total) * 35
        let criticalPenalty = (criticalCount / total) * 65
        return min(max(100 - warningPenalty - criticalPenalty, 0), 100)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        isGatherConfirmationPresented = true
                    } label: {
                        Label("Gather Diagnostics", systemImage: "waveform.path.ecg")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)

                    SupportInfoButton(
                        title: "Gather Diagnostics",
                        helpText: "Refreshes the selected device detail and diagnostics payload from Jamf Pro."
                    )
                }
            } header: {
                Text("Controls")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack(spacing: 12) {
                    SupportFieldRow(key: "Operating System", value: osDisplayValue)

                    Button {
                        onUpdateOperatingSystem()
                    } label: {
                        Label("Update OS", systemImage: "square.and.arrow.down.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: 200, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)
                }
            } header: {
                Text("Operating System")
            }

            Section {
                managerShortcutRow(
                    title: "Applications",
                    count: detail.applications.count,
                    systemImage: "app.badge",
                    action: onOpenApplicationManager
                )

                managerShortcutRow(
                    title: "Configuration Profiles",
                    count: detail.configurationProfiles.count,
                    systemImage: "gear.badge.checkmark",
                    action: onOpenConfigurationProfileManager
                )

                managerShortcutRow(
                    title: "Group Memberships",
                    count: detail.groupMemberships.count,
                    systemImage: "person.3.sequence",
                    action: onOpenGroupMembershipManager
                )

                managerShortcutRow(
                    title: "Local User Accounts",
                    count: detail.localUserAccounts.count,
                    systemImage: "person.2",
                    action: onOpenAccountManager
                )

                managerShortcutRow(
                    title: "Certificates",
                    count: detail.certificates.count,
                    systemImage: "checkmark.seal",
                    action: onOpenCertificateManager
                )
            } header: {
                Text("Manager Shortcuts")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        isErrorLogsExpanded.toggle()
                    } label: {
                        Label("Error Logs", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                    SupportInfoButton(
                        title: "Error Logs",
                        helpText: "Open device log controls, then choose Get Logs to fetch available logs or queue log collection from the target."
                    )
                }

                if isErrorLogsExpanded {
                    HStack(spacing: 10) {
                        Button {
                            isGetLogsConfirmationPresented = true
                        } label: {
                            Label("Get Logs", systemImage: "arrow.down.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                        .disabled(isPerformingAction)

                        SupportInfoButton(
                            title: "Get Logs",
                            helpText: "Fetches available logs now. If logs are not yet available, a request command is sent so the target can upload logs on next check-in."
                        )
                    }

                    if let latestDeviceLogs,
                       latestDeviceLogs.isEmpty == false
                    {
                        Text(latestDeviceLogs)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)

                        HStack(spacing: 10) {
                            Button {
                                BrandClipboard.copy(latestDeviceLogs)
                            } label: {
                                Label("Copy Logs", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.appSecondary)
                            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                            SupportInfoButton(
                                title: "Copy Logs",
                                helpText: "Copies the latest retrieved device logs to clipboard."
                            )
                        }
                    }
                }
            } header: {
                Text("Error Logs")
            }

            if hasServicesSection {
                Section {
                    HStack(spacing: 10) {
                        Button {
                            isServicesDetailPresented = true
                        } label: {
                            Label("Open Services Detail", systemImage: "wrench.and.screwdriver")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appSecondary)
                        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)

                        SupportInfoButton(
                            title: "Services Detail",
                            helpText: "Opens an expanded services view for service-related inventory data."
                        )
                    }
                } header: {
                    Text("Services")
                }
            }

            Section {
                HStack(spacing: 20) {
                    SupportHealthIndicatorView(
                        score: healthScore,
                        warningCount: severityMetrics.first(where: { $0.id == "warning" })?.count ?? 0,
                        criticalCount: severityMetrics.first(where: { $0.id == "critical" })?.count ?? 0
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SupportSeverityBarChartView(metrics: severityMetrics)
                        .frame(maxWidth: .infinity, minHeight: 150)
                }
            } header: {
                Text("Diagnostic Indicators")
            }

            Section {
                if let storageUsedMB,
                   let storageCapacityMB,
                   storageCapacityMB > 0
                {
                    SupportCapacityChartView(
                        title: "Storage Capacity",
                        usedValue: storageUsedMB,
                        totalValue: storageCapacityMB,
                        usedColor: .orange,
                        unitLabel: "MB"
                    )
                }

                if let memoryUsedMB,
                   let memoryTotalMB,
                   memoryTotalMB > 0
                {
                    SupportCapacityChartView(
                        title: "RAM Capacity",
                        usedValue: memoryUsedMB,
                        totalValue: memoryTotalMB,
                        usedColor: .blue,
                        unitLabel: "MB"
                    )
                }

                if let cpuIndicatorPercent {
                    SupportGaugeMetricView(
                        title: "CPU Use",
                        value: cpuIndicatorPercent,
                        maximum: 100,
                        color: .red,
                        suffix: "%"
                    )
                }

                if let batteryLevelPercent {
                    SupportGaugeMetricView(
                        title: "Battery Status",
                        value: batteryLevelPercent,
                        maximum: 100,
                        color: .green,
                        suffix: "%"
                    )
                }

                if let uptimeHours {
                    SupportGaugeMetricView(
                        title: "Uptime",
                        value: uptimeHours,
                        maximum: max(uptimeHours, 24),
                        color: .purple,
                        suffix: "h"
                    )
                }
            } header: {
                Text("Device Metrics Charts")
            }

            Section {
                if metrics.isEmpty {
                    Text("No numeric hardware metrics were available from inventory for chart rendering.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(metric.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Text("\(metric.value, specifier: "%.0f")%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: metric.value, total: 100)
                                .tint(metric.color)
                        }
                        .padding(.vertical, 2)
                    }

                    if let storageUsedPercent {
                        SupportPieChartView(usedPercent: storageUsedPercent)
                            .frame(height: 170)
                    }

                    SupportLineChartView(values: metrics.map(\.value))
                        .frame(height: 160)
                }
            } header: {
                Text("Hardware Graphics")
            }

            Section {
                ForEach(detail.diagnostics) { diagnostic in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(diagnostic.title)
                            .font(.subheadline.weight(.semibold))
                        Text(diagnostic.value)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Diagnostic Summary")
            }

            ForEach(filteredSectionsForDiagnostics) { section in
                Section {
                    ForEach(section.items) { item in
                        SupportFieldRow(key: item.key, value: item.value)
                    }
                } header: {
                    Text(section.title)
                }
            }

            Section {
                DisclosureGroup("Show JSON", isExpanded: $isRawJSONExpanded) {
                    ScrollView(.horizontal) {
                        Text(detail.rawJSON)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("Raw Payload")
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Diagnostic View")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert("Gather Diagnostics?", isPresented: $isGatherConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onRefreshDiagnostics()
            }
        } message: {
            Text("Refresh diagnostics data for the selected device from Jamf Pro.")
        }
        .alert("Get Error Logs?", isPresented: $isGetLogsConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onRequestErrorLogs()
            }
        } message: {
            Text("Fetch available logs now or queue a device log request for the target.")
        }
        .sheet(isPresented: $isServicesDetailPresented) {
            SupportServicesDetailSheet(
                serviceSections: serviceSections,
                rawJSON: detail.rawJSON
            )
        }
    }

    /// Handles numericValue.
    @ViewBuilder
    private func managerShortcutRow(
        title: String,
        count: Int,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                action()
            } label: {
                HStack(spacing: 10) {
                    Label(title, systemImage: systemImage)
                        .font(.body.weight(.semibold))

                    Spacer(minLength: 0)

                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BrandTheme.groupedSurface)
                        .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.appSecondary)
            .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
        }
    }

    /// Handles normalizeSectionTitle.
    private func normalizeSectionTitle(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    /// Handles numericValue.
    private func numericValue(matching fragments: [String]) -> Double? {
        for (key, value) in flattenedValues {
            let normalizedKey = key.lowercased()
            if fragments.contains(where: { normalizedKey.contains($0) }) {
                if let number = firstNumber(in: value) {
                    return number
                }
            }
        }

        return nil
    }

    /// Handles firstNumber.
    private func firstNumber(in value: String) -> Double? {
        let pattern = #"[-+]?\d*\.?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let fullRange = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: fullRange),
              let range = Range(match.range, in: value)
        else {
            return nil
        }

        return Double(value[range])
    }

    /// Handles clampPercent.
    private func clampPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

/// SupportHealthIndicatorView declaration.
private struct SupportHealthIndicatorView: View {
    let score: Double
    let warningCount: Int
    let criticalCount: Int

    private var clampedScore: Double {
        min(max(score, 0), 100)
    }

    private var strokeColor: Color {
        if clampedScore >= 80 {
            return .green
        }
        if clampedScore >= 50 {
            return .orange
        }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health Indicator")
                .font(.subheadline.weight(.semibold))

            ZStack {
                Circle()
                    .stroke(BrandTheme.groupedSurface, lineWidth: 16)

                Circle()
                    .trim(from: 0, to: clampedScore / 100)
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(clampedScore, specifier: "%.0f")")
                        .font(.title3.weight(.bold))
                    Text("Score")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            Text("Warnings: \(warningCount) • Critical: \(criticalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// SupportSeverityBarChartView declaration.
private struct SupportSeverityBarChartView: View {
    struct Metric: Identifiable {
        let id: String
        let label: String
        let count: Int
        let color: Color
    }

    let metrics: [Metric]

    private var maxCount: Double {
        Double(metrics.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Severity Distribution")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(metrics) { metric in
                    VStack(spacing: 6) {
                        Text("\(metric.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(metric.color.opacity(0.9))
                            .frame(
                                width: 34,
                                height: CGFloat(max((Double(metric.count) / maxCount) * 92, 10))
                            )

                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 120, alignment: .bottomLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BrandTheme.groupedSurface.opacity(0.55))
            )
        }
    }
}

/// SupportCapacityChartView declaration.
private struct SupportCapacityChartView: View {
    let title: String
    let usedValue: Double
    let totalValue: Double
    let usedColor: Color
    let unitLabel: String

    private var clampedUsed: Double {
        min(max(usedValue, 0), totalValue)
    }

    private var remainingValue: Double {
        max(totalValue - clampedUsed, 0)
    }

    private var usedPercent: Double {
        guard totalValue > 0 else {
            return 0
        }

        return (clampedUsed / totalValue) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 0)

                Text("\(usedPercent, specifier: "%.0f")%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let usedWidth = width * CGFloat(usedPercent / 100)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BrandTheme.groupedSurface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(usedColor.opacity(0.85))
                        .frame(width: usedWidth)
                }
            }
            .frame(height: 16)

            Text("Used: \(clampedUsed, specifier: "%.0f") \(unitLabel) • Free: \(remainingValue, specifier: "%.0f") \(unitLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// SupportGaugeMetricView declaration.
private struct SupportGaugeMetricView: View {
    let title: String
    let value: Double
    let maximum: Double
    let color: Color
    let suffix: String

    private var normalizedPercent: Double {
        guard maximum > 0 else {
            return 0
        }

        return min(max((value / maximum) * 100, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(value, specifier: "%.1f")\(suffix)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: normalizedPercent, total: 100)
                .tint(color)
        }
    }
}

/// SupportPieChartView declaration.
private struct SupportPieChartView: View {
    let usedPercent: Double

    private var usedSlice: Double {
        min(max(usedPercent / 100, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storage Pie")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(BrandTheme.groupedSurface, lineWidth: 24)

                    Circle()
                        .trim(from: 0, to: usedSlice)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(usedPercent, specifier: "%.0f")%")
                            .font(.headline.weight(.semibold))
                        Text("Used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Used", systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                    Label("Free", systemImage: "circle.fill")
                        .foregroundStyle(BrandTheme.groupedSurface)
                    Text("Free: \(max(0, 100 - usedPercent), specifier: "%.0f")%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// SupportLineChartView declaration.
private struct SupportLineChartView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geometry in
            let normalized = values.map { min(max($0, 0), 100) }
            let points = normalized.enumerated().map { index, value -> CGPoint in
                let stepX = normalized.count > 1 ? geometry.size.width / CGFloat(normalized.count - 1) : 0
                let x = CGFloat(index) * stepX
                let y = geometry.size.height * (1 - CGFloat(value / 100))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(BrandTheme.groupedSurface.opacity(0.55))

                Path { path in
                    guard let first = points.first else {
                        return
                    }

                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(BrandColors.bluePrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(BrandColors.bluePrimary)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
        }
    }
}

/// SupportCertificateManagerView declaration.
private struct SupportCertificateManagerView: View {
    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGoBack: () -> Void
    let onRenewMDMProfile: () -> Void
    let onAddCertificate: (String, String?) -> Void
    let onRemoveCertificate: (SupportCertificate) -> Void

    @State private var certificateNameDraft = ""
    @State private var profileIdentifierDraft = ""
    @State private var pendingRemovalCertificate: SupportCertificate?
    @State private var isRenewConfirmationPresented = false
    @State private var isAddConfirmationPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        isRenewConfirmationPresented = true
                    } label: {
                        Label("Renew MDM Profile Certificate", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)

                    SupportInfoButton(
                        title: "Renew MDM Profile Certificate",
                        helpText: "Queues Jamf Pro Renew MDM Profile, which renews the device identity certificate."
                    )
                }
            } header: {
                Text("Certificate Actions")
            }

            Section {
                TextField("Certificate/Profile Name", text: $certificateNameDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("Profile Identifier (optional)", text: $profileIdentifierDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        isAddConfirmationPresented = true
                    } label: {
                        Label("Add Certificate", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(
                        isPerformingAction ||
                            certificateNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    SupportInfoButton(
                        title: "Add Certificate",
                        helpText: "Uses certificate-related modern API guidance in this module workflow."
                    )
                }
            } header: {
                Text("Add")
            }

            Section {
                if detail.certificates.isEmpty {
                    Text("No certificates returned in inventory for this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.certificates) { certificate in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(certificate.commonName)
                                    .font(.subheadline.weight(.semibold))

                                if let subjectName = certificate.subjectName,
                                   subjectName.isEmpty == false
                                {
                                    Text(subjectName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                if let expirationDate = certificate.expirationDate,
                                   expirationDate.isEmpty == false
                                {
                                    Text("Expires: \(expirationDate)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)

                            Button("Delete", role: .destructive) {
                                pendingRemovalCertificate = certificate
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPerformingAction)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Installed Certificates")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Certificate Manager")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert("Renew MDM Profile Certificate?", isPresented: $isRenewConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onRenewMDMProfile()
            }
        } message: {
            Text("Queue Renew MDM Profile to renew the device identity certificate.")
        }
        .alert("Add Certificate?", isPresented: $isAddConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onAddCertificate(certificateNameDraft, profileIdentifierDraft)
            }
        } message: {
            Text("Add the provided certificate/profile reference to this device workflow.")
        }
        .alert(
            "Remove Certificate?",
            isPresented: Binding(
                get: { pendingRemovalCertificate != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingRemovalCertificate = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingRemovalCertificate = nil
            }

            Button("Remove", role: .destructive) {
                guard let pendingRemovalCertificate else {
                    return
                }

                onRemoveCertificate(pendingRemovalCertificate)
                self.pendingRemovalCertificate = nil
            }
        } message: {
            Text("Remove selected certificate from the targeted device.")
        }
    }
}

/// SupportConfigurationProfileManagerView declaration.
private struct SupportConfigurationProfileManagerView: View {
    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGoBack: () -> Void
    let onReload: () -> Void
    let onAddProfile: (String, String?) -> Void
    let onRemoveProfile: (SupportConfigurationProfile) -> Void

    @State private var profileNameDraft = ""
    @State private var profileIdentifierDraft = ""
    @State private var pendingRemovalProfile: SupportConfigurationProfile?
    @State private var isReloadConfirmationPresented = false
    @State private var isAddConfirmationPresented = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        isReloadConfirmationPresented = true
                    } label: {
                        Label("Reload Profiles", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)

                    SupportInfoButton(
                        title: "Reload Profiles",
                        helpText: "Refreshes configuration profile data from Jamf inventory."
                    )
                }
            } header: {
                Text("Profile Catalog")
            }

            Section {
                TextField("Profile Name", text: $profileNameDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("Profile Identifier (optional)", text: $profileIdentifierDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        isAddConfirmationPresented = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(
                        isPerformingAction ||
                            profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    SupportInfoButton(
                        title: "Add Profile",
                        helpText: "Queues or guides a profile-add workflow for the selected device."
                    )
                }
            } header: {
                Text("Add")
            }

            Section {
                if detail.configurationProfiles.isEmpty {
                    Text("No configuration profiles were returned in inventory for this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.configurationProfiles) { profile in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(.subheadline.weight(.semibold))

                                if let identifier = profile.identifier,
                                   identifier.isEmpty == false
                                {
                                    Text(identifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                if let profileStatus = profile.profileStatus,
                                   profileStatus.isEmpty == false
                                {
                                    Text("Status: \(profileStatus)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)

                            Button("Remove", role: .destructive) {
                                pendingRemovalProfile = profile
                            }
                            .buttonStyle(.bordered)
                            .disabled(isPerformingAction)
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Configuration Profiles")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Configuration Profile Manager")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert("Reload Profiles?", isPresented: $isReloadConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onReload()
            }
        } message: {
            Text("Refresh configuration profile inventory for this device.")
        }
        .alert("Add Profile?", isPresented: $isAddConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onAddProfile(profileNameDraft, profileIdentifierDraft)
            }
        } message: {
            Text("Add the provided configuration profile reference to this device workflow.")
        }
        .alert(
            "Remove Configuration Profile?",
            isPresented: Binding(
                get: { pendingRemovalProfile != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingRemovalProfile = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingRemovalProfile = nil
            }

            Button("Remove", role: .destructive) {
                guard let pendingRemovalProfile else {
                    return
                }

                onRemoveProfile(pendingRemovalProfile)
                self.pendingRemovalProfile = nil
            }
        } message: {
            Text("Remove selected configuration profile from the targeted device.")
        }
    }
}

/// SupportGroupMembershipManagerView declaration.
private struct SupportGroupMembershipManagerView: View {
    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGoBack: () -> Void
    let onReload: () -> Void
    let onAddMembership: (String, String?) -> Void
    let onRemoveMembership: (SupportGroupMembership) -> Void

    @State private var selectedMembershipID: String?
    @State private var groupNameDraft = ""
    @State private var groupTypeDraft = ""
    @State private var pendingRemovalMembership: SupportGroupMembership?
    @State private var isReloadConfirmationPresented = false
    @State private var isAddConfirmationPresented = false

    private var selectedMembership: SupportGroupMembership? {
        detail.groupMemberships.first(where: { $0.id == selectedMembershipID })
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        isReloadConfirmationPresented = true
                    } label: {
                        Label("Reload Memberships", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)

                    SupportInfoButton(
                        title: "Reload Memberships",
                        helpText: "Refreshes group membership data from Jamf inventory."
                    )
                }

                TextField("Group Name", text: $groupNameDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("Group Type (optional)", text: $groupTypeDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        isAddConfirmationPresented = true
                    } label: {
                        Label("Add Membership", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || groupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    SupportInfoButton(
                        title: "Add Membership",
                        helpText: "Adds the target device to the named group membership workflow."
                    )
                }
            } header: {
                SupportSectionHeader(
                    title: "Membership Catalog",
                    helpText: "Group manager uses the same catalog -> select -> action flow as Application Manager."
                )
            }

            Section {
                if detail.groupMemberships.isEmpty {
                    Text("No group memberships were returned for this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.groupMemberships) { group in
                        Button {
                            selectedMembershipID = group.id
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "person.3")
                                    .foregroundStyle(.tint)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name)
                                        .font(.body.weight(.semibold))

                                    if let groupType = group.groupType,
                                       groupType.isEmpty == false
                                    {
                                        Text(groupType)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let isSmartGroup = group.isSmartGroup {
                                        Text(isSmartGroup ? "Smart Group" : "Static Group")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(BrandTheme.groupedSurface)
                                            .clipShape(Capsule())
                                    }
                                }

                                Spacer(minLength: 0)

                                if selectedMembershipID == group.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BrandColors.greenPrimary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                SupportSectionHeader(
                    title: "Group Memberships",
                    helpText: "Select one membership to target remove operations."
                )
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        if let selectedMembership {
                            pendingRemovalMembership = selectedMembership
                        }
                    } label: {
                        Label("Remove Membership", systemImage: "minus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appDanger)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || selectedMembership == nil)

                    SupportInfoButton(
                        title: "Remove Membership",
                        helpText: "Removes the selected group membership from the target device."
                    )
                }

                if selectedMembership == nil {
                    Text("Select a group membership above before running remove.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SupportSectionHeader(
                    title: "Membership Actions",
                    helpText: "Run membership management actions against the selected device."
                )
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Group Membership Manager")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert("Reload Memberships?", isPresented: $isReloadConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onReload()
            }
        } message: {
            Text("Refresh group membership inventory for this device.")
        }
        .alert("Add Membership?", isPresented: $isAddConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                onAddMembership(groupNameDraft, groupTypeDraft)
            }
        } message: {
            Text("Add this device to the specified group membership workflow.")
        }
        .alert(
            "Remove Group Membership?",
            isPresented: Binding(
                get: { pendingRemovalMembership != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingRemovalMembership = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingRemovalMembership = nil
            }

            Button("Remove", role: .destructive) {
                guard let pendingRemovalMembership else {
                    return
                }

                onRemoveMembership(pendingRemovalMembership)
                self.pendingRemovalMembership = nil
            }
        } message: {
            Text("Remove selected group membership from the targeted device.")
        }
    }
}

/// SupportLocalUserControlView declaration.
private struct SupportLocalUserControlView: View {
    private enum AccountControlConfirmation {
        case addAccount
        case unlockAccount(username: String)
        case deleteAccount(username: String)
        case editAccount(username: String, accountGUID: String?)
        case resetPassword(accountGUID: String)
        case setPIN
        case clearPIN
        case clearRestrictionsPIN

        var title: String {
            switch self {
            case .addAccount:
                return "Add Account?"
            case .unlockAccount:
                return "Unlock Account?"
            case .deleteAccount:
                return "Delete Account?"
            case .editAccount:
                return "Edit Account?"
            case .resetPassword:
                return "Reset Password?"
            case .setPIN:
                return "Reset/Change PIN?"
            case .clearPIN:
                return "Clear PIN?"
            case .clearRestrictionsPIN:
                return "Clear Restrictions PIN?"
            }
        }

        var message: String {
            switch self {
            case .addAccount:
                return "Create the local account with the provided username and temporary password."
            case let .unlockAccount(username):
                return "Unlock account '\(username)' on the selected device."
            case let .deleteAccount(username):
                return "Delete account '\(username)' from the selected device."
            case let .editAccount(username, _):
                return "Apply profile/password edits for account '\(username)'."
            case .resetPassword:
                return "Send Jamf password reset command for the selected account GUID."
            case .setPIN:
                return "Set a new device lock PIN using the entered values."
            case .clearPIN:
                return "Clear the device lock PIN using the provided unlock token."
            case .clearRestrictionsPIN:
                return "Clear restrictions PIN on the selected mobile device."
            }
        }

        var confirmRole: ButtonRole? {
            switch self {
            case .deleteAccount:
                return .destructive
            default:
                return nil
            }
        }
    }

    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGoBack: () -> Void
    let onAddAccount: (String, String, String) -> Void
    let onDeleteAccount: (String) -> Void
    let onResetPassword: (String, String) -> Void
    let onUnlockAccount: (String) -> Void
    let onEditAccount: (String, String, String?, String) -> Void
    let onSetPIN: (String, String?, String?) -> Void
    let onClearPIN: (String) -> Void
    let onClearRestrictionsPIN: () -> Void

    @State private var usernameDraft = ""
    @State private var fullNameDraft = ""
    @State private var addPasswordDraft = ""
    @State private var selectedAccountIDForEdit: String?
    @State private var editedFullNameDraft = ""
    @State private var editedPasswordDraft = ""
    @State private var selectedAccountIDForReset: String?
    @State private var resetPasswordDraft = ""
    @State private var pinDraft = ""
    @State private var lockMessageDraft = ""
    @State private var phoneNumberDraft = ""
    @State private var unlockTokenDraft = ""
    @State private var pendingConfirmation: AccountControlConfirmation?

    private var selectedAccountForEdit: SupportLocalUserAccount? {
        detail.localUserAccounts.first(where: { $0.id == selectedAccountIDForEdit })
    }

    private var selectedAccountForReset: SupportLocalUserAccount? {
        detail.localUserAccounts.first(where: { $0.id == selectedAccountIDForReset })
    }

    var body: some View {
        List {
            Section {
                TextField("Username", text: $usernameDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("Full Name", text: $fullNameDraft)
                    .textFieldStyle(.roundedBorder)

                SecureField("Temporary Password", text: $addPasswordDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button {
                        pendingConfirmation = .addAccount
                    } label: {
                        Label("Add Account", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(
                        isPerformingAction ||
                            usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            addPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    SupportInfoButton(
                        title: "Add Account",
                        helpText: "Attempts local user account creation workflow for the selected managed device."
                    )
                }
            } header: {
                Text("Add Account")
            }

            Section {
                if detail.localUserAccounts.isEmpty {
                    Text("No local user account inventory is available for this device.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.localUserAccounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(account.username)
                                    .font(.subheadline.weight(.semibold))

                                Spacer(minLength: 0)

                                if account.isAdmin == true {
                                    Text("Admin")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(BrandColors.blueSecondary.opacity(0.28))
                                        .clipShape(Capsule())
                                }
                            }

                            if let fullName = account.fullName,
                               fullName.isEmpty == false
                            {
                                Text(fullName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button("Unlock") {
                                    pendingConfirmation = .unlockAccount(username: account.username)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isPerformingAction)

                                Button("Delete", role: .destructive) {
                                    pendingConfirmation = .deleteAccount(username: account.username)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isPerformingAction)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            } header: {
                Text("Accounts")
            }

            Section {
                if detail.localUserAccounts.isEmpty {
                    Text("No account available for edit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Account", selection: $selectedAccountIDForEdit) {
                        Text("Select Account").tag(String?.none)
                        ForEach(detail.localUserAccounts) { account in
                            Text(account.username).tag(String?.some(account.id))
                        }
                    }

                    TextField("Updated Full Name (optional)", text: $editedFullNameDraft)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Updated Password (optional)", text: $editedPasswordDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        guard let selectedAccountForEdit else {
                            return
                        }

                        pendingConfirmation = .editAccount(
                            username: selectedAccountForEdit.username,
                            accountGUID: selectedAccountForEdit.userGuid
                        )
                    } label: {
                        Label("Edit Account", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(
                        isPerformingAction ||
                        selectedAccountForEdit == nil ||
                        (
                            editedFullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                            editedPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) ||
                        (
                            editedPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
                            selectedAccountForEdit?.userGuid?.isEmpty != false
                        )
                    )

                    if editedPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                       selectedAccountForEdit?.userGuid?.isEmpty != false
                    {
                        Text("Selected account does not include a GUID in inventory. Password edits require account GUID.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Edit Account")
            }

            Section {
                if detail.localUserAccounts.isEmpty {
                    Text("No account available for password reset.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Account", selection: $selectedAccountIDForReset) {
                        Text("Select Account").tag(String?.none)
                        ForEach(detail.localUserAccounts) { account in
                            Text(account.username).tag(String?.some(account.id))
                        }
                    }

                    SecureField("New Password", text: $resetPasswordDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        guard let selectedAccountForReset,
                              let guid = selectedAccountForReset.userGuid,
                              guid.isEmpty == false
                        else {
                            return
                        }

                        pendingConfirmation = .resetPassword(accountGUID: guid)
                    } label: {
                        Label("Reset Password", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(
                        isPerformingAction ||
                        selectedAccountForReset?.userGuid?.isEmpty != false ||
                        resetPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if selectedAccountForReset?.userGuid?.isEmpty != false {
                        Text("Selected account does not include a GUID in inventory. Jamf password-reset command requires account GUID.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Reset Password")
            }

            if detail.summary.assetType == .mobileDevice {
                Section {
                    SecureField("New PIN", text: $pinDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Lock Message (optional)", text: $lockMessageDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Phone Number (optional)", text: $phoneNumberDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        pendingConfirmation = .setPIN
                    } label: {
                        Label("Reset/Change PIN", systemImage: "lock.rotation")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || pinDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Set PIN")
                }

                Section {
                    TextField("Unlock Token (Base64)", text: $unlockTokenDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        pendingConfirmation = .clearPIN
                    } label: {
                        Label("Clear PIN", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || unlockTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Clear PIN")
                }

                Section {
                    Button {
                        pendingConfirmation = .clearRestrictionsPIN
                    } label: {
                        Label("Clear Restrictions PIN", systemImage: "number.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)
                } header: {
                    Text("Restrictions")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Account Manager")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert(
            pendingConfirmation?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingConfirmation = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingConfirmation = nil
            }

            Button("Confirm", role: pendingConfirmation?.confirmRole) {
                guard let pendingConfirmation else {
                    return
                }

                switch pendingConfirmation {
                case .addAccount:
                    onAddAccount(usernameDraft, fullNameDraft, addPasswordDraft)
                case let .unlockAccount(username):
                    onUnlockAccount(username)
                case let .deleteAccount(username):
                    onDeleteAccount(username)
                case let .editAccount(username, accountGUID):
                    onEditAccount(username, editedFullNameDraft, accountGUID, editedPasswordDraft)
                case let .resetPassword(accountGUID):
                    onResetPassword(accountGUID, resetPasswordDraft)
                case .setPIN:
                    onSetPIN(pinDraft, lockMessageDraft, phoneNumberDraft)
                case .clearPIN:
                    onClearPIN(unlockTokenDraft)
                case .clearRestrictionsPIN:
                    onClearRestrictionsPIN()
                }

                self.pendingConfirmation = nil
            }
        } message: {
            Text(pendingConfirmation?.message ?? "")
        }
        .onChange(of: selectedAccountIDForEdit) { _, accountID in
            guard let accountID,
                  let account = detail.localUserAccounts.first(where: { $0.id == accountID })
            else {
                editedFullNameDraft = ""
                editedPasswordDraft = ""
                return
            }

            editedFullNameDraft = account.fullName ?? ""
            editedPasswordDraft = ""
        }
    }
}

/// SupportMobilePINControlView declaration.
private struct SupportMobilePINControlView: View {
    private enum PINControlConfirmation {
        case setPIN
        case clearPIN
        case clearRestrictionsPIN

        var title: String {
            switch self {
            case .setPIN:
                return "Reset/Change PIN?"
            case .clearPIN:
                return "Clear PIN?"
            case .clearRestrictionsPIN:
                return "Clear Restrictions PIN?"
            }
        }

        var message: String {
            switch self {
            case .setPIN:
                return "Set a new device PIN using the provided values."
            case .clearPIN:
                return "Clear the device lock PIN with the unlock token."
            case .clearRestrictionsPIN:
                return "Clear restrictions PIN on this mobile device."
            }
        }
    }

    let detail: SupportDeviceDetail
    let isPerformingAction: Bool
    let statusMessage: String?
    let errorMessage: String?
    let onGoBack: () -> Void
    let onSetPIN: (String, String?, String?) -> Void
    let onClearPIN: (String) -> Void
    let onClearRestrictionsPIN: () -> Void

    @State private var pinDraft = ""
    @State private var lockMessageDraft = ""
    @State private var phoneNumberDraft = ""
    @State private var unlockTokenDraft = ""
    @State private var pendingConfirmation: PINControlConfirmation?

    var body: some View {
        List {
            if detail.summary.assetType != .mobileDevice {
                Section {
                    Text("Mobile PIN controls are available only for mobile devices.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    SecureField("New PIN", text: $pinDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Lock Message (optional)", text: $lockMessageDraft)
                        .textFieldStyle(.roundedBorder)

                    TextField("Phone Number (optional)", text: $phoneNumberDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        pendingConfirmation = .setPIN
                    } label: {
                        Label("Reset/Change PIN", systemImage: "lock.rotation")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || pinDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Set PIN")
                }

                Section {
                    TextField("Unlock Token (Base64)", text: $unlockTokenDraft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        pendingConfirmation = .clearPIN
                    } label: {
                        Label("Clear PIN", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction || unlockTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Clear PIN")
                }

                Section {
                    Button {
                        pendingConfirmation = .clearRestrictionsPIN
                    } label: {
                        Label("Clear Restrictions PIN", systemImage: "number.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                    .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                    .disabled(isPerformingAction)
                } header: {
                    Text("Restrictions")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Mobile PIN Control")
        .appInlineNavigationTitle()
        .supportDetailBackChevron(onGoBack: onGoBack)
        .alert(
            pendingConfirmation?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingConfirmation = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingConfirmation = nil
            }

            Button("Confirm") {
                guard let pendingConfirmation else {
                    return
                }

                switch pendingConfirmation {
                case .setPIN:
                    onSetPIN(pinDraft, lockMessageDraft, phoneNumberDraft)
                case .clearPIN:
                    onClearPIN(unlockTokenDraft)
                case .clearRestrictionsPIN:
                    onClearRestrictionsPIN()
                }

                self.pendingConfirmation = nil
            }
        } message: {
            Text(pendingConfirmation?.message ?? "")
        }
    }
}

/// SupportServicesDetailSheet declaration.
private struct SupportServicesDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let serviceSections: [SupportDetailSection]
    let rawJSON: String
    @State private var isRawExpanded = false

    var body: some View {
        NavigationStack {
            List {
                if serviceSections.isEmpty {
                    Section {
                        Text("No service-specific inventory sections were returned.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(serviceSections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                SupportFieldRow(key: item.key, value: item.value)
                            }
                        }
                    }
                }

                Section("Raw Payload") {
                    DisclosureGroup("Show JSON", isExpanded: $isRawExpanded) {
                        ScrollView(.horizontal) {
                            Text(rawJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .appInsetGroupedListStyle()
            .navigationTitle("Services Detail")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
    }
}

/// SupportTypedRemovalConfirmationSheet declaration.
private struct SupportTypedRemovalConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let action: SupportManagementAction
    @Binding var confirmationText: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var canConfirm: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == "Remove"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirmation Required") {
                    Text("You are about to run \(action.title).")
                        .font(.body.weight(.semibold))

                    Text("Type Remove to continue.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Remove", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Confirm \(action.title)", role: .destructive) {
                        guard canConfirm else {
                            return
                        }

                        onConfirm()
                        dismiss()
                    }
                    .disabled(canConfirm == false)

                    Button("Cancel", role: .cancel) {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .appInsetGroupedListStyle()
            .navigationTitle("Type Remove")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .interactiveDismissDisabled(canConfirm == false)
    }
}

/// SupportSectionHeader declaration.
private struct SupportSectionHeader: View {
    let title: String
    let helpText: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 0)

            SupportInfoButton(
                title: title,
                helpText: helpText
            )
        }
        .textCase(nil)
    }
}

private extension View {
    /// Adds a consistent back chevron that returns to the previous Support Technician pane.
    func supportDetailBackChevron(
        onGoBack: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .appTopBarLeading) {
                Button {
                    onGoBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
                .disabled(isEnabled == false)
            }
        }
    }
}

/// SupportInfoButton declaration.
private struct SupportInfoButton: View {
    let title: String
    let helpText: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(BrandColors.bluePrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(BrandTheme.groupedSurface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Help: \(title)")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(.headline)

                Text(helpText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(minWidth: 260, maxWidth: 340, alignment: .leading)
        }
    }
}

/// SupportFieldRow declaration.
private struct SupportFieldRow: View {
    let key: String
    let value: String

    private static let acronymMap: [String: String] = [
        "api": "API",
        "cpu": "CPU",
        "id": "ID",
        "imei": "IMEI",
        "ip": "IP",
        "laps": "LAPS",
        "mac": "MAC",
        "mdm": "MDM",
        "os": "OS",
        "pin": "PIN",
        "ram": "RAM",
        "udid": "UDID",
        "url": "URL",
        "uuid": "UUID"
    ]

    private var formattedKey: String {
        let camelSeparated = key.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )

        let normalized = camelSeparated
            .replacingOccurrences(of: "[_\\-.]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = normalized.split(whereSeparator: { $0.isWhitespace })
        guard words.isEmpty == false else {
            return key
        }

        return words.map { token in
            let rawWord = String(token)
            let lowerWord = rawWord.lowercased()

            if let acronym = Self.acronymMap[lowerWord] {
                return acronym
            }

            if rawWord.allSatisfy(\.isNumber) {
                return rawWord
            }

            return lowerWord.prefix(1).uppercased() + lowerWord.dropFirst()
        }
        .joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formattedKey)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 164, alignment: .leading)

            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

//endofline
