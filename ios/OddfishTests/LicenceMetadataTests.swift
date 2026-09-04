import Foundation
import Testing
@testable import Oddfish

@MainActor
struct LicenceMetadataTests {
    @Test func readsTheExactReleaseIdentityAndSourceURL() throws {
        let metadata = LicenceMetadata(infoDictionary: [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "17",
            LicenceMetadata.sourceCodeURLInfoKey: "https://source.oddfish.app/releases/1.0.0-17"
        ])

        #expect(metadata.version == "1.0.0")
        #expect(metadata.build == "17")
        #expect(metadata.versionLabel == "Version 1.0.0 (17)")
        #expect(metadata.compactVersionLabel == "1.0.0 (17)")
        #expect(metadata.sourceCodeURL?.absoluteString == "https://source.oddfish.app/releases/1.0.0-17")
    }

    @Test func trimsBuildMetadataBeforePresentingIt() {
        let metadata = LicenceMetadata(infoDictionary: [
            "CFBundleShortVersionString": " 1.0.0 ",
            "CFBundleVersion": " 1 "
        ])

        #expect(metadata.versionLabel == "Version 1.0.0 (1)")
    }

    @Test(arguments: [
        nil,
        "",
        "$(ODDFISH_SOURCE_CODE_URL)",
        "http://source.oddfish.app/releases/1",
        "https://localhost/source",
        "https://127.0.0.1/source",
        "https://example.com/source",
        "https://code.example.org/source",
        "https://example.net/source",
        "https://source.invalid/release",
        "<public-source-url>"
    ] as [String?])
    func rejectsMissingInsecureAndPlaceholderSourceURLs(value: String?) {
        #expect(LicenceMetadata.validSourceCodeURL(value) == nil)
    }

    @Test func missingBuildMetadataHasAnHonestDevelopmentLabel() {
        let metadata = LicenceMetadata(infoDictionary: [:])

        #expect(metadata.versionLabel == "Development build")
        #expect(metadata.sourceCodeURL == nil)
    }
}
