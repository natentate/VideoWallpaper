import Foundation

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case displays
    case library
    case favorites
    case discover
    case create
    case focus
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .displays: return "Now Playing"
        case .library: return "Library"
        case .favorites: return "Favorites"
        case .discover: return "Discover"
        case .create: return "Create"
        case .focus: return "Focus Modes"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .displays: return "display.2"
        case .library: return "film.stack"
        case .favorites: return "heart"
        case .discover: return "globe"
        case .create: return "wand.and.stars"
        case .focus: return "moon.circle"
        case .settings: return "gearshape"
        }
    }
}
