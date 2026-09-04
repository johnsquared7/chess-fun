import SwiftUI

/// Release identity and source-offer metadata embedded in the app's Info.plist.
///
/// `OddfishSourceCodeURL` is populated from the `ODDFISH_SOURCE_CODE_URL`
/// build setting. Release builds refuse to archive without a valid HTTPS URL;
/// keeping the parser defensive prevents a malformed value from becoming a
/// convincing-looking but unusable link.
struct LicenceMetadata: Equatable {
    static let sourceCodeURLInfoKey = "OddfishSourceCodeURL"

    let version: String
    let build: String
    let sourceCodeURL: URL?

    init(infoDictionary: [String: Any]) {
        version = Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"]) ?? ""
        build = Self.nonEmptyString(infoDictionary["CFBundleVersion"]) ?? ""
        sourceCodeURL = Self.validSourceCodeURL(infoDictionary[Self.sourceCodeURLInfoKey])
    }

    static var current: LicenceMetadata {
        LicenceMetadata(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    var versionLabel: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): "Version \(version) (\(build))"
        case (false, true): "Version \(version)"
        case (true, false): "Build \(build)"
        case (true, true): "Development build"
        }
    }

    var compactVersionLabel: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): "\(version) (\(build))"
        case (false, true): version
        case (true, false): "Build \(build)"
        case (true, true): "Development"
        }
    }

    static func validSourceCodeURL(_ value: Any?) -> URL? {
        guard let rawValue = nonEmptyString(value),
              !rawValue.contains("$("),
              !rawValue.contains("<"),
              !rawValue.contains(">"),
              let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host != "localhost",
              host != "127.0.0.1",
              !["example.com", "example.org", "example.net"].contains(where: {
                  host == $0 || host.hasSuffix(".\($0)")
              }),
              !host.hasSuffix(".example"),
              !host.hasSuffix(".invalid") else {
            return nil
        }

        return components.url
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The licence notice and corresponding-source offer shown inside the app.
struct LicenceView: View {
    private let metadata: LicenceMetadata

    init(metadata: LicenceMetadata = .current) {
        self.metadata = metadata
    }

    var body: some View {
        Form {
            Section {
                Text("Oddfish is free software under the GNU General Public License, version 3 or later.")
                    .font(.oddfishBody)

                LabeledContent("Release", value: metadata.versionLabel)
            } header: {
                Text("Licence")
            } footer: {
                Text("You may use, study, modify and share it under the terms of that licence.")
            }

            Section {
                if let url = metadata.sourceCodeURL {
                    Link(destination: url) {
                        LabeledContent("Complete source") {
                            Text(url.host() ?? url.absoluteString)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("licence-source-link")
                } else {
                    LabeledContent("Complete source") {
                        Text("Not configured")
                            .foregroundStyle(OddfishTheme.coral)
                    }
                    .accessibilityIdentifier("licence-source-missing")
                }
            } header: {
                Text("Source code")
            } footer: {
                if metadata.sourceCodeURL == nil {
                    Text("This development build has no source URL. Release builds are blocked until a public source archive is configured.")
                } else {
                    Text("The link identifies the complete corresponding source for this release, including Oddfish's engine integration.")
                }
            }

            Section {
                NavigationLink("GNU GPL version 3") {
                    BundledLicenceView()
                }
                .accessibilityIdentifier("licence-full-text")

                LabeledContent("Stockfish 18", value: "GPLv3")
                LabeledContent("Neural networks", value: "GPLv3")
                Text("Oddfish drives Stockfish through its public engine interface; the bundled engine source is otherwise unmodified.")
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
            } header: {
                Text("Included software")
            } footer: {
                Text("The complete GNU GPL text is included with every copy of Oddfish.")
            }

            Section {
                ForEach(PieceSet.allCases) { set in
                    if let credit = set.credit {
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(set.title, value: credit.licence)
                            Text("\(credit.author) · \(credit.source)")
                                .font(.oddfishCaption)
                                .foregroundStyle(OddfishTheme.mutedInk)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text("Piece artwork")
            } footer: {
                Text("Oddfish's pieces are converted from their artist's own drawings and are credited above. The board, its themes, Gil and everything else drawn in Oddfish are original to it.")
            }
        }
        .navigationTitle("Licence")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BundledLicenceView: View {
    private let licenceText: String

    init(bundle: Bundle = .main) {
        licenceText = Self.loadLicence(from: bundle)
    }

    var body: some View {
        ScrollView {
            Text(licenceText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(OddfishTheme.ivory)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(OddfishTheme.canvas)
        .navigationTitle("GNU GPL v3")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func loadLicence(from bundle: Bundle) -> String {
        guard let url = bundle.url(forResource: "COPYING", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty else {
            return "The bundled GNU GPL licence text could not be loaded."
        }

        return text
    }
}

#Preview("Configured") {
    NavigationStack {
        LicenceView(metadata: LicenceMetadata(infoDictionary: [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
            LicenceMetadata.sourceCodeURLInfoKey: "https://source.oddfish.app/releases/1.0.0-1"
        ]))
    }
}
