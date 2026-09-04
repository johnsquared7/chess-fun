import Testing
@testable import Oddfish

@Suite("Startup gate sequencing")
struct StartupGateTests {
    @Test func brandIsRetainedUntilHomeHasBeenInserted() {
        #expect(OddfishStartupPhase.brandOnly.showsBrand)
        #expect(!OddfishStartupPhase.brandOnly.showsHome)

        #expect(OddfishStartupPhase.preparingHome.showsBrand)
        #expect(OddfishStartupPhase.preparingHome.showsHome)

        #expect(!OddfishStartupPhase.home.showsBrand)
        #expect(OddfishStartupPhase.home.showsHome)
    }
}
