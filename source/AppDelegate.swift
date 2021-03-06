import Cocoa

class AppDelegate:NSObject, NSApplicationDelegate {
	private lazy var windowController = BrowserWindowController()
	lazy var applicationName:String = {
		if let bundleName = Bundle.main.object(forInfoDictionaryKey:"CFBundleName") {
			if let bundleNameAsString = bundleName as? String {
				return bundleNameAsString
			}
			else {
				NSLog("CFBundleName not a String!")
			}
		}
		else {
			NSLog("CFBundleName nil!")
		}
		
		return NSLocalizedString("Bonjeff", comment:"The name of this application")
	}()
	
	func applicationWillFinishLaunching(_ notification:Notification) {
		populateMainMenu()
	}
	
	func applicationDidFinishLaunching(_ notification:Notification) {
		windowController.open(applicationName)
	}
	
	func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {
		return true
	}
	
	@objc func openWebSite(_ sender:Any?) {
		if let myURL = URL(string:"https://github.com/lapcat/Bonjeff") {
			NSWorkspace.shared.open(myURL)
		}
	}
	
	@objc func openLicense(_ sender:Any?) {
		LicenseWindowController.open()
	}
}
