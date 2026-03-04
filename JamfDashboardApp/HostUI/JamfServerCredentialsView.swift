import SwiftUI

/// ServerCredentialsView declaration.
struct ServerCredentialsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var credentialsStore: JamfCredentialsStore
    let diagnosticsReporter: (any DiagnosticsReporting)?

    @State private var serverURL = ""
    @State private var authenticationMethod = JamfCredentials.AuthenticationMethod.apiClient
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var accountUsername = ""
    @State private var accountPassword = ""
    @State private var isVerifyingConnection = false
    @State private var isConnectionVerified = false

    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var verificationInputSignature: String {
        switch authenticationMethod {
        case .apiClient:
            return [
                authenticationMethod.rawValue,
                serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret
            ].joined(separator: "|")
        case .usernamePassword:
            return [
                authenticationMethod.rawValue,
                serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                accountUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                accountPassword
            ].joined(separator: "|")
        }
    }

    private var canVerifyConnection: Bool {
        credentialsForFormState().isComplete
    }

    var body: some View {
        Form {
            Section("Jamf Server") {
                TextField("https://company.jamfcloud.com", text: $serverURL)
                    .appURLKeyboard()
                    .appNoAutoCorrectionTextInput()
            }

            Section("Authentication Method") {
                Picker("Method", selection: $authenticationMethod) {
                    ForEach(JamfCredentials.AuthenticationMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose one method. Only the selected method is used and stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if authenticationMethod == .apiClient {
                Section("Jamf API Client") {
                    TextField("Client ID", text: $clientID)
                        .appNoAutoCorrectionTextInput()
                    SecureField("Client Secret", text: $clientSecret)
                }
            } else {
                Section("Jamf Account") {
                    TextField("Username", text: $accountUsername)
                        .appNoAutoCorrectionTextInput()
                    SecureField("Password", text: $accountPassword)
                }
            }

            Section {
                Button {
                    Task {
                        await verifyConnection()
                    }
                } label: {
                    if isVerifyingConnection {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verifying Connection...")
                        }
                    } else {
                        Text("Verify Connection")
                    }
                }
                .buttonStyle(.appSecondary)
                .disabled(canVerifyConnection == false || isVerifyingConnection)

                Button("Save Credentials") {
                    saveCredentials()
                }
                .buttonStyle(.appPrimary)
                .disabled(isConnectionVerified == false || isVerifyingConnection)

                Button("Clear Stored Credentials", role: .destructive) {
                    clearCredentials()
                }
                .buttonStyle(.appDanger)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(BrandColors.greenPrimary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .appInsetGroupedListStyle()
        .navigationTitle("Server Credentials")
        .appInlineNavigationTitle()
        .onChange(of: verificationInputSignature) { _, _ in
            resetVerificationStateForInputChange()
        }
        .task {
            loadExistingCredentialsIfPresent()
        }
    }

    /// Handles loadExistingCredentialsIfPresent.
    private func loadExistingCredentialsIfPresent() {
        guard let credentials = try? credentialsStore.loadCredentials() else {
            return
        }

        serverURL = credentials.serverURL
        authenticationMethod = credentials.authenticationMethod
        clientID = credentials.clientID
        clientSecret = credentials.clientSecret
        accountUsername = credentials.accountUsername
        accountPassword = credentials.accountPassword
        isConnectionVerified = false
    }

    /// Handles credentialsForFormState.
    private func credentialsForFormState() -> JamfCredentials {
        switch authenticationMethod {
        case .apiClient:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .apiClient,
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: "",
                accountPassword: ""
            )
        case .usernamePassword:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .usernamePassword,
                clientID: "",
                clientSecret: "",
                accountUsername: accountUsername,
                accountPassword: accountPassword
            )
        }
    }

    /// Handles verifyConnection.
    @MainActor
    private func verifyConnection() async {
        guard canVerifyConnection else {
            statusMessage = nil
            errorMessage = "Complete the server URL and selected login fields to verify."
            isConnectionVerified = false
            return
        }

        isVerifyingConnection = true
        isConnectionVerified = false
        statusMessage = nil
        errorMessage = nil

        let credentials = credentialsForFormState()
        let authenticationService = JamfAuthenticationService(diagnosticsReporter: diagnosticsReporter)

        do {
            _ = try await authenticationService.accessToken(for: credentials)
            isConnectionVerified = true
            statusMessage = "Connection verified. You can now save credentials."
            errorMessage = nil

            await diagnosticsReporter?.report(
                source: "framework.credentials",
                category: "verification",
                severity: .info,
                message: "Jamf credential verification succeeded.",
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
        } catch {
            isConnectionVerified = false
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            await diagnosticsReporter?.reportError(
                source: "framework.credentials",
                category: "verification",
                message: "Jamf credential verification failed.",
                errorDescription: description,
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
        }

        isVerifyingConnection = false
    }

    /// Handles saveCredentials.
    private func saveCredentials() {
        guard isConnectionVerified else {
            statusMessage = nil
            errorMessage = "Verify the connection before saving credentials."
            return
        }

        do {
            let credentials = credentialsForFormState()

            try credentialsStore.saveCredentials(credentials)
            statusMessage = "Credentials saved securely in Keychain."
            errorMessage = nil

            Task {
                await diagnosticsReporter?.report(
                    source: "framework.credentials",
                    category: "credentials",
                    severity: .info,
                    message: "Jamf credentials saved to Keychain.",
                    metadata: [:]
                )
            }
        } catch {
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            Task {
                await diagnosticsReporter?.reportError(
                    source: "framework.credentials",
                    category: "credentials",
                    message: "Failed to save Jamf credentials.",
                    errorDescription: description
                )
            }
        }
    }

    /// Handles clearCredentials.
    private func clearCredentials() {
        do {
            try credentialsStore.clearCredentials()
            statusMessage = "Stored credentials removed."
            errorMessage = nil
            serverURL = ""
            authenticationMethod = .apiClient
            clientID = ""
            clientSecret = ""
            accountUsername = ""
            accountPassword = ""
            isConnectionVerified = false

            Task {
                await diagnosticsReporter?.report(
                    source: "framework.credentials",
                    category: "credentials",
                    severity: .warning,
                    message: "Stored Jamf credentials were cleared.",
                    metadata: [:]
                )
            }
        } catch {
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            Task {
                await diagnosticsReporter?.reportError(
                    source: "framework.credentials",
                    category: "credentials",
                    message: "Failed to clear stored credentials.",
                    errorDescription: description
                )
            }
        }
    }

    /// Handles resetVerificationStateForInputChange.
    private func resetVerificationStateForInputChange() {
        guard isConnectionVerified else {
            return
        }

        isConnectionVerified = false
        statusMessage = nil
    }
}

//endofline
