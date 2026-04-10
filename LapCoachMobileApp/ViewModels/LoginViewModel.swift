import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let submitAction: (String, String) async throws -> Void

    init(submitAction: @escaping (String, String) async throws -> Void) {
        self.submitAction = submitAction
    }

    var canSubmit: Bool {
        email.contains("@") && password.isEmpty == false && isLoading == false
    }

    func signIn() async -> Bool {
        errorMessage = nil
        isLoading = true

        do {
            try await submitAction(email, password)
            isLoading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        return false
    }
}
