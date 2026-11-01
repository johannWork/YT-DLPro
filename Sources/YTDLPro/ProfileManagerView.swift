import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileManagerView: View {
    @ObservedObject var downloads: DownloadCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var newProfileName = ""
    @State private var renameValues: [UUID: String] = [:]
    @State private var alertMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Download Profiles").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            HStack {
                TextField("New profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                Button("Save Current Settings", systemImage: "plus") {
                    downloads.saveCurrentProfile(named: newProfileName)
                    newProfileName = ""
                }
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)

            List(downloads.profiles) { profile in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(profile.name).fontWeight(.medium)
                            if profile.isBuiltIn {
                                Text("Built-in").font(.caption2).foregroundStyle(.secondary)
                            }
                            if !profile.outputFolder.isEmpty {
                                Image(systemName: "folder").help(profile.outputFolder)
                            }
                        }
                        Text(summary(for: profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Load", systemImage: "checkmark") { downloads.selectProfile(profile.id) }
                        .labelStyle(.iconOnly)
                        .help("Load profile")
                    if !profile.isBuiltIn {
                        Button("Rename", systemImage: "pencil") {
                            renameValues[profile.id] = profile.name
                            alertMessage = "rename:\(profile.id.uuidString)"
                        }
                        .labelStyle(.iconOnly)
                        .help("Rename profile")
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") { downloads.duplicateProfile(profile.id) }
                        .labelStyle(.iconOnly)
                        .help("Duplicate profile")
                    if !profile.isBuiltIn {
                        Button("Choose profile folder", systemImage: "folder") { chooseProfileFolder(profile) }
                            .labelStyle(.iconOnly)
                            .help("Set profile default output folder")
                        Button("Delete", systemImage: "trash") { downloads.deleteProfile(profile.id) }
                            .labelStyle(.iconOnly)
                            .help("Delete profile")
                    }
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button("Import…", systemImage: "square.and.arrow.down", action: importProfiles)
                Button("Export…", systemImage: "square.and.arrow.up", action: exportProfiles)
                Spacer()
                Text("\(downloads.profiles.count) profiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(width: 720, height: 560)
        .alert(errorMessage == nil ? "Rename Profile" : "Unable to process profiles", isPresented: Binding(
            get: { errorMessage != nil || alertMessage?.hasPrefix("rename:") == true },
            set: {
                if !$0 {
                    errorMessage = nil
                    alertMessage = nil
                }
            }
        )) {
            if errorMessage != nil {
                Button("OK", role: .cancel) { errorMessage = nil }
            } else {
                TextField("Profile name", text: renameBinding)
                Button("Cancel", role: .cancel) { alertMessage = nil }
                Button("Save") {
                    if let profileID = renameProfileID {
                        downloads.renameProfile(profileID, to: renameBinding.wrappedValue)
                    }
                    alertMessage = nil
                }
            }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    private var renameProfileID: UUID? {
        guard let value = alertMessage?.split(separator: ":").last else { return nil }
        return UUID(uuidString: String(value))
    }

    private var renameBinding: Binding<String> {
        Binding(
            get: { renameProfileID.flatMap { renameValues[$0] } ?? "" },
            set: { if let id = renameProfileID { renameValues[id] = $0 } }
        )
    }

    private func summary(for profile: DownloadProfile) -> String {
        let kind = profile.options.mediaType.rawValue
        let detail = profile.options.mediaType == .audioOnly ? profile.options.audioFormat.rawValue.uppercased() : profile.options.resolution.rawValue
        return profile.outputFolder.isEmpty ? "\(kind) · \(detail)" : "\(kind) · \(detail) · \(profile.outputFolder)"
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try downloads.importProfiles(from: url) }
            catch { showError(error) }
        }
    }

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "YT-DLPro-profiles.json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try downloads.exportProfiles(to: url) }
            catch { showError(error) }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private func chooseProfileFolder(_ profile: DownloadProfile) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.directoryURL = profile.outputFolder.isEmpty ? nil : URL(fileURLWithPath: profile.outputFolder)
        if panel.runModal() == .OK, let url = panel.url {
            downloads.setProfileFolder(profile.id, to: url.path)
        }
    }
}
