import Cocoa

// This is a generic base class to be subclassed
class BrowserDelegate:NSObject, NetServiceBrowserDelegate, BonjourNode {
	let browser = NetServiceBrowser()
	
	// These need to be overridden
	var children:[Any] { preconditionFailure() }
	lazy var objectValue:String = { preconditionFailure() }()
	lazy var persistentName:String = { preconditionFailure() }()
	
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
