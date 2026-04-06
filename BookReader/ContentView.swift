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
                let oldValue = self.selectedTab
                print("ContentView tabSelection set: old=\(oldValue) new=\(newValue)")
                
                // If double-tapping the current tab, naturally pop to root
                if newValue == oldValue {
                    if newValue == 0 {
                        homeNavigationPath = []
                    } else if newValue == 1 {
                        libraryNavigationPath = []
                    }
                } else {
                    // Cross-tab routing: Enforce clean boundaries by clearing the OUTGOING tab's path.
                    // Clearing the *incoming* tab synchronously causes a ghost overlay bug on iOS 16+.
                    if oldValue == 0 {
                        homeNavigationPath = []
                    } else if oldValue == 1 {
                        libraryNavigationPath = []
                    }
                }
                
                self.selectedTab = newValue
                print("ContentView tabSelection end: selectedTab=\(self.selectedTab) homePathCount=\(homeNavigationPath.count) libraryPathCount=\(libraryNavigationPath.count)")
            }
        )
    }
    
    private func applyTabBarAppearance(for tab: Int) {
        guard AppConfig.shared.isMonetizationBeta else { return }
        // Dispatched async so the UITabBarController is guaranteed to be in
        // the view hierarchy before we walk it.
        DispatchQueue.main.async {
            TabBarAppearanceManager.apply(for: tab)
        }
    }
    
    var body: some View {
        mainTabView
            .onAppear {
                if AppConfig.shared.isMonetizationBeta && !hasSeenLibraryWelcome {
                    selectedTab = 1
                }
                applyTabBarAppearance(for: selectedTab)
            }
            .onChange(of: selectedTab) { newValue in
                applyTabBarAppearance(for: newValue)
                print("ContentView onChange(selectedTab): \(newValue) homePathCount=\(homeNavigationPath.count) libraryPathCount=\(libraryNavigationPath.count)")
            }
            .onChange(of: homeNavigationPath) { newValue in
                print("ContentView onChange(homeNavigationPath): count=\(newValue.count)")
            }
            .onChange(of: libraryNavigationPath) { newValue in
                print("ContentView onChange(libraryNavigationPath): count=\(newValue.count)")
            }
    }
    
    private var mainTabView: some View {
        TabView(selection: tabSelection) {
            homeTab
            libraryTab
            settingsTab
        }
    }
    
    private var homeTab: some View {
        NavigationStack(path: $homeNavigationPath) {
            HomeView(
                libraryManager: libraryManager,
                selectedTab: $selectedTab,
                navigationPath: $homeNavigationPath,
                libraryPath: $libraryNavigationPath
            )
        }
        .tabItem {
            Label("Now Playing", systemImage: "play.circle.fill")
        }
        .tag(0)
    }
    
    private var libraryTab: some View {
        NavigationStack(path: $libraryNavigationPath) {
            LibraryView(
                libraryManager: libraryManager,
                selectedTab: $selectedTab,
                navigationPath: $libraryNavigationPath
            )
        }
        .tabItem {
            Label("Library", systemImage: "books.vertical.fill")
        }
        .tag(1)
    }
    
    private var settingsTab: some View {
        NavigationStack {
            SettingsView()
        }
        .tabItem {
            Label("Settings", systemImage: "gearshape.fill")
        }
        .tag(2)
    }
}
