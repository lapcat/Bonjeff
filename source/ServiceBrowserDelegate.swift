import Cocoa

class ServiceBrowserDelegate:BrowserDelegate {
	let domain:String
	let type:String
	var delegates = [ServiceDelegate]()
	override var children:[Any] { return delegates }
	override var objectValue:String { return type }
	
	required init(type:String, domain:String) {
		self.type = type
		self.domain = domain
		super.init()
		let name = type + domain
		persistentName = name.lowercased()
	}
	
	@available(*, unavailable)
	override init() {
		fatalError()
	}
	
	override func start() {
		super.start()
		browser.searchForServices(ofType:type, inDomain:domain)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didFind service:NetService, moreComing:Bool) {
		for delegate in delegates {
			if delegate.service == service {
				NSLog("didFind duplicate service:%@", service)
				return
			}
		}
		
		let newDelegate = ServiceDelegate(service)
		delegates.append(newDelegate)
		delegates.sort { $0.service.name < $1.service.name }
		NotificationCenter.default.post(name:.nodeDidAdd, object:newDelegate)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didRemove service:NetService, moreComing:Bool) {
		for (index, delegate) in delegates.enumerated() {
			if delegate.service == service {
				delegates.remove(at:index)
				delegate.stop()
				NotificationCenter.default.post(name:.nodeDidRemove, object:self)
				return
			}
		}
	}
}

