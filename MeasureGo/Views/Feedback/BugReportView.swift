//
//  BugReportView.swift
//  MeasureGo
//
//  Feedback / bug-report form — port of Unity's BugReportPopup:
//  report type (Bug / Proposition / Other), subject, description, reporter
//  email, optional log attachment, sent by email.
//

import SwiftUI
import MessageUI

struct BugReportView: View {

    enum ReportType: String, CaseIterable, Identifiable {
        case bug = "Bug"
        case proposition = "Proposition"
        case other = "Other"
        var id: String { rawValue }
    }

    /// Same recipient as the Unity app.
    static let recipient = "egoroleinik12@gmail.com"

    @Environment(\.dismiss) private var dismiss

    @State private var reportType: ReportType = .bug
    @State private var subject = ""
    @State private var descriptionText = ""
    @State private var email = ""
    @State private var attachLogs = true
    @State private var attachPreviousLogs = true

    @State private var showValidationAlert = false
    @State private var showMailComposer = false
    @State private var showNoMailAlert = false

    private var isValid: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && InputRules.isValidEmail(email)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $reportType) {
                        ForEach(ReportType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Subject") {
                    TextField("Short summary", text: $subject)
                }

                Section("Description") {
                    TextField("What happened?", text: $descriptionText, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section {
                    TextField("your@email.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Your email")
                } footer: {
                    if !email.isEmpty && !InputRules.isValidEmail(email) {
                        Text("Invalid email address").foregroundStyle(.red)
                    }
                }

                if reportType == .bug {
                    Section {
                        Toggle("Attach app logs", isOn: $attachLogs)
                        if attachLogs {
                            Toggle("Attach previous session logs", isOn: $attachPreviousLogs)
                        }
                    } footer: {
                        Text("Logs help us reproduce the problem. They contain app events and device info only.")
                    }
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                }
            }
            .alert("Please fill in all fields", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Subject, description and a valid email address are required.")
            }
            .alert("No email account", isPresented: $showNoMailAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set up an email account on this device, or write to \(Self.recipient) directly.")
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposeView(
                    recipient: Self.recipient,
                    subject: subject,
                    body: composeBody()
                ) { sent in
                    showMailComposer = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func send() {
        guard isValid else {
            showValidationAlert = true
            return
        }
        AppLog.log("Feedback submitted: \(reportType.rawValue)")

        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else if let url = mailtoURL() {
            // Fall back to the system mail handler (Unity used mailto: only).
            UIApplication.shared.open(url) { opened in
                if opened { dismiss() } else { showNoMailAlert = true }
            }
        } else {
            showNoMailAlert = true
        }
    }

    private func composeBody() -> String {
        var body = "[\(reportType.rawValue)]\n\(descriptionText)\n\(email)\n\n"
        body += "App: \(AppLog.appVersion)\nDevice: \(AppLog.deviceIdentifier)\n"

        if reportType == .bug && attachLogs {
            body += "\n[LOGS]\n" + AppLog.currentLogContent()
            if attachPreviousLogs {
                for previous in AppLog.previousLogContents() {
                    body += "\n\n[PREVIOUS LOGS]\n" + previous
                }
            }
        } else {
            body += "\nNo logs attached"
        }
        return body
    }

    private func mailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            // mailto has practical length limits — send a trimmed body.
            URLQueryItem(name: "body", value: String(composeBody().prefix(2000))),
        ]
        return components.url
    }
}

// MARK: - Mail composer

private struct MailComposeView: UIViewControllerRepresentable {

    let recipient: String
    let subject: String
    let body: String
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result == .sent)
        }
    }
}
