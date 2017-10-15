import Cocoa

protocol BonjourNode:NSObjectProtocol {
	var children:[Any] { get }
	var objectValue:String { get }
	var persistentName:String { get set }
	func start()
	func stop()
}

extension Notification.Name {
	static let nodeDidAdd = Notification.Name("nodeDidAdd")
	static let nodeDidRemove = Notification.Name("nodeDidRemove")
	static let nodeDidUpdate = Notification.Name("nodeDidUpdate")
}
