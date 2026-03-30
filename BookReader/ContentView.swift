//
//  ContentView.swift
//  BookReader
//
//  Created by Dave Marvit on 1/25/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var libraryManager: LibraryManager
    
    @State private var selectedTab = 0
    @State private var homeNavigationPath: [NavigationDestination] = []
    @State private var libraryNavigationPath: [NavigationDestination] = []
    
    @AppStorage("hasSeenLibraryWelcome") private var hasSeenLibraryWelcome = false
    
    // Intercept user tab bar taps specifically
    private var tabSelection: Binding<Int> {
        Binding(
            get: { self.selectedTab },
            set: { newValue in
                print("ContentView tabSelection set: old=\(self.selectedTab) new=\(newValue)")
                // Only reset the path if tapping the ALREADY active tab (tap-to-root)
                if newValue == self.selectedTab {
                    if newValue == 0 {
                        print("ContentView clearing homeNavigationPath")
                        homeNavigationPath = []
                    } else if newValue == 1 {
                        print("ContentView clearing libraryNavigationPath")
                        libraryNavigationPath = []
                    }
                }
                self.selectedTab = newValue
                print("ContentView tabSelection end: selectedTab=\(self.selectedTab) homePathCount=\(homeNavigationPath.count) libraryPathCount=\(libraryNavigationPath.count)")
            }
        )
    }
    
    private func updateTabBarAppearance(for tab: Int) {
        if AppConfig.shared.isMonetizationBeta && tab == 0 {
            // Immersive background is only on Now Playing (tab 0)
            UITabBar.appearance().unselectedItemTintColor = UIColor(white: 1.0, alpha: 0.6)
        } else {
            // Revert to system default
            UITabBar.appearance().unselectedItemTintColor = .systemGray
        }
    }
    
    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $homeNavigationPath) {
                HomeView(libraryManager: libraryManager, selectedTab: $selectedTab, navigationPath: $homeNavigationPath)
            }
            .tabItem {
                Label("Now Playing", systemImage: "play.circle.fill")
            }
            .tag(0)
            
            NavigationStack(path: $libraryNavigationPath) {
                LibraryView(libraryManager: libraryManager, navigationPath: $libraryNavigationPath)
            }
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }
            .tag(1)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .onAppear {
            if AppConfig.shared.isMonetizationBeta && !hasSeenLibraryWelcome {
                selectedTab = 1
            }
            updateTabBarAppearance(for: selectedTab)
        }
        .onChange(of: selectedTab) { newValue in
            updateTabBarAppearance(for: newValue)
            print("ContentView onChange(selectedTab): \(newValue) homePathCount=\(homeNavigationPath.count) libraryPathCount=\(libraryNavigationPath.count)")
        }
        .onChange(of: homeNavigationPath) { newValue in
            print("ContentView onChange(homeNavigationPath): count=\(newValue.count)")
        }
        .onChange(of: libraryNavigationPath) { newValue in
            print("ContentView onChange(libraryNavigationPath): count=\(newValue.count)")
        }
    }
}
