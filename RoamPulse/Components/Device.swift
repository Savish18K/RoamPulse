import UIKit

// "iPhone" or "iPad", so messages like "kept on this iPhone" are right on both
@MainActor
enum Device {
    static var name: String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
    static var symbol: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }
}
