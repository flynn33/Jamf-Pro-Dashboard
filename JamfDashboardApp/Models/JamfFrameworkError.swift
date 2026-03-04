import Foundation
import Security

/// JamfFrameworkError declaration.
enum JamfFrameworkError: LocalizedError {
    case invalidServerURL
    case missingCredentials
    case invalidCredentials
    case authenticationFailed
    case networkFailure(statusCode: Int, message: String)
    case decodingFailure
    case keychainFailure(status: OSStatus)
    case persistenceFailure(message: String)
    case invalidModulePackage(message: String)
    case duplicateModulePackage(packageID: String)
    case unsupportedModulePackageType(type: String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The Jamf Pro URL is invalid."
        case .missingCredentials:
            return "Jamf credentials are missing."
        case .invalidCredentials:
            return "Credentials are incomplete for the selected sign-in method."
        case .authenticationFailed:
            return "Authentication with the Jamf Pro server failed."
        case let .networkFailure(statusCode, message):
            return "Request failed with status \(statusCode): \(message)"
        case .decodingFailure:
            return "The server response format is not supported."
        case let .keychainFailure(status):
            return "Keychain operation failed with status \(status)."
        case let .persistenceFailure(message):
            return "Local persistence failed: \(message)"
        case let .invalidModulePackage(message):
            return "Invalid module package: \(message)"
        case let .duplicateModulePackage(packageID):
            return "A module package with id '\(packageID)' is already installed."
        case let .unsupportedModulePackageType(type):
            return "Unsupported module package type '\(type)'."
        }
    }
}

//endofline
