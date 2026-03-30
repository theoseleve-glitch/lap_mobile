import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel: LoginViewModel

    init(appModel: LapCoachAppModel) {
        _viewModel = StateObject(
            wrappedValue: LoginViewModel { email, password in
                try await appModel.signIn(email: email, password: password)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Lap Coach")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Record live telemetry, keep every session local first, and sync it back to your account when the network cooperates.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(BrandTheme.heroGradient)
                )

                VStack(alignment: .leading, spacing: 18) {
                    Text("Sign In")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BrandTheme.ink)

                    Group {
                        TextField("Email", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        SecureField("Password", text: $viewModel.password)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.04))
                    )

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(BrandTheme.danger)
                    }

                    Button {
                        Task {
                            await viewModel.signIn()
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(viewModel.isLoading ? "Signing In..." : "Continue")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(viewModel.canSubmit ? BrandTheme.ink : BrandTheme.muted)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(viewModel.canSubmit == false)
                }
                .appCard()
            }
            .padding(20)
        }
    }
}
