import Cocoa

// This is a generic base class to be subclassed
class BrowserDelegate:NSObject, NetServiceBrowserDelegate, BonjourNode {
	let browser = NetServiceBrowser()
	
	// These need to be overridden
	var children:[Any] { fatalError() }
	lazy var objectValue:String = { fatalError() }()
	lazy var persistentName:String = { fatalError() }()
	
	func start() {
		browser.includesPeerToPeer = true
		browser.delegate = self
	}
	
	func stop() {
		browser.delegate = nil
		browser.stop()
		for child in children {
			if let node = child as? BonjourNode {
				node.stop()
			}
		}
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didNotSearch errorDict:[String:NSNumber]) {
		NSLog("netServiceBrowser:%@ didNotSearch:%@", sender, errorDict)
	}
}
