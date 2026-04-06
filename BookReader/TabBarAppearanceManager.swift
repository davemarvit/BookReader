//
//  TabBarAppearanceManager.swift
//  BookReader
//

import UIKit

enum TabBarAppearanceManager {

    // MARK: — Pre-built appearances (created once, never mutated)

    /// Transparent bar with white/translucent icons for the immersive Now Playing screen.
    static let immersive: UITabBarAppearance = {
        let a = UITabBarAppearance()
        a.configureWithTransparentBackground()

        let iconColor = UIColor.white.withAlphaComponent(0.6)
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: iconColor]

        for layout in [a.stackedLayoutAppearance,
                       a.inlineLayoutAppearance,
                       a.compactInlineLayoutAppearance] {
            layout.normal.iconColor = iconColor
            layout.normal.titleTextAttributes = attrs
            // Keep selected state distinct so the active tab is obvious
            layout.selected.iconColor = UIColor.white
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        }
        return a
    }()

    /// Clean system-default bar for Library and Settings.
    static let `default`: UITabBarAppearance = {
        let a = UITabBarAppearance()
        a.configureWithDefaultBackground()
        // No further customisation — let the system render tint etc. naturally.
        return a
    }()

    // MARK: — Application

    /// Applies the correct appearance directly to the live UITabBar instance.
    /// Must be called on the main thread.
    static func apply(for tab: Int, isRoot: Bool) {
        guard let tabBar = liveTabBar() else { return }
        
        let useImmersive = (tab == 0 && isRoot)
        let appearance = useImmersive ? immersive : `default`
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        
        // Force legacy tint constraints to prevent SwiftUI navigation pushes 
        // from silently overriding UITabBarItemAppearance items via proxy limits
        if useImmersive {
            tabBar.tintColor = .white
            tabBar.unselectedItemTintColor = UIColor.white.withAlphaComponent(0.6)
        } else {
            tabBar.tintColor = nil
            tabBar.unselectedItemTintColor = nil
        }
    }

    // MARK: — Private

    private static func liveTabBar() -> UITabBar? {
        // Walk the key window's root view controller hierarchy to find UITabBarController.
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
              let root = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        return findTabBarController(in: root)?.tabBar
    }

    private static func findTabBarController(in vc: UIViewController) -> UITabBarController? {
        if let tbc = vc as? UITabBarController { return tbc }
        if let tbc = vc.children.compactMap({ findTabBarController(in: $0) }).first { return tbc }
        if let presented = vc.presentedViewController {
            return findTabBarController(in: presented)
        }
        return nil
    }
}
