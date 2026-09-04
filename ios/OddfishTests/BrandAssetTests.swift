import Testing
import UIKit
@testable import Oddfish

@Suite("Brand assets")
struct BrandAssetTests {
    @Test @MainActor
    func splitOMarkIsBundledOnItsSquareCanvas() {
        let mark = UIImage(named: "OddfishMark")

        #expect(mark != nil)
        if let mark {
            #expect(mark.size.width == mark.size.height)
            #expect(mark.size.width == 120)
        }
    }

    @Test @MainActor
    func retiredLaunchArtworkIsNotBundled() {
        #expect(UIImage(named: "LaunchBrand") == nil)
    }
}
