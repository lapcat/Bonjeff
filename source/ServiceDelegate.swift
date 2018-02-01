import Cocoa

class ServiceDelegate:NSObject, NetServiceDelegate, BonjourNode {
	let service:NetService
	private var resolved = [(String, String)]()
	private var records = [(String, String)]()
	var children:[Any] { return resolved + records }
	lazy var objectValue:String = service.name
	lazy var persistentName:String = "\(service.name).\(service.type)\(service.domain)".lowercased()
	private lazy var hostKey = NSLocalizedString("Host", comment:"Host of net service")
	private lazy var portKey = NSLocalizedString("Port", comment:"Port of net service")
	private var started = false
	
	required init(_ service:NetService) {
		self.service = service
		super.init()
	}
	
	@available(*, unavailable)
	override init() {
		fatalError()
	}
	
	func start() {
		if !started {
			started = true
			reloadTXTRecord()
			service.delegate = self
			service.startMonitoring()
			service.resolve(withTimeout:0.0)
		}
	}
	
	func stop() {
		if started {
			started = false
			service.delegate = nil
			service.stopMonitoring()
			service.stop()
		}
	}
	
	func netServiceDidResolveAddress(_ sender:NetService) {
		resolved.removeAll()
		
		if let hostName = service.hostName {
			resolved.append( (hostKey, hostName) )
		}
		let port = service.port
		if port > 0 {
			resolved.append( (portKey, "\(port)") )
		}
		if let addresses = service.addresses {
			for data in addresses {
				data.withUnsafeBytes {(bytes:UnsafePointer<sockaddr>) in
					let family = Int32(bytes.pointee.sa_family)
					switch family {
					case AF_INET:
						bytes.withMemoryRebound(to:sockaddr_in.self, capacity:1) {
							var addr = $0.pointee.sin_addr
							let size = Int(INET_ADDRSTRLEN)
							let buffer = UnsafeMutablePointer<Int8>.allocate(capacity:size)
							if let cString = inet_ntop(family, &addr, buffer, socklen_t(size)) {
								let line = String(cString:cString)
								resolved.append( ("", line) )
							}
							else {
								NSLog("inet_ntop errno %i from %@", errno, data as NSData)
							}
							#if swift(>=4.1)
								buffer.deallocate()
							#else
								buffer.deallocate(capacity:size)
							#endif
						}
					case AF_INET6:
						bytes.withMemoryRebound(to:sockaddr_in6.self, capacity:1) {
							var addr = $0.pointee.sin6_addr
							let size = Int(INET6_ADDRSTRLEN)
							let buffer = UnsafeMutablePointer<Int8>.allocate(capacity:size)
							if let cString = inet_ntop(family, &addr, buffer, socklen_t(size)) {
								let line = String(cString:cString)
								resolved.append( ("", line) )
							}
							else {
								NSLog("inet_ntop errno %i from %@", errno, data as NSData)
							}
							#if swift(>=4.1)
								buffer.deallocate()
							#else
								buffer.deallocate(capacity:size)
							#endif
						}
						
					default:
						NSLog("Unexpected address family: %i", family)
					}
				}
			}
		}
		
		reloadTXTRecord() // The TXT Record can update in netServiceDidResolveAddress without necessarily calling didUpdateTXTRecord
		NotificationCenter.default.post(name:.nodeDidUpdate, object:self)
	}
	
	func netService(_ sender:NetService, didNotResolve errorDict:[String:NSNumber]) {
		NSLog("didNotResolve:%@ errorDict:%@", sender, errorDict)
	}
	
	func netService(_ sender:NetService, didUpdateTXTRecord data:Data) {
		reloadTXTRecord()
		NotificationCenter.default.post(name:.nodeDidUpdate, object:self)
	}
	
	func reloadTXTRecord() {
		records.removeAll()
		
		if let txtRecordData = service.txtRecordData() {
			let txtRecord = NetService.dictionary(fromTXTRecord:txtRecordData)
			for (key, data) in txtRecord {
				if let line = NSString(data:data, encoding:String.Encoding.utf8.rawValue) {
					records.append( (key, line as String) )
				}
				else {
					records.append( (key, data.description) )
				}
			}
			// Sort by key in (key, value)
			records.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
		}
	}
}
