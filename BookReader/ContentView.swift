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
                // If the user taps a tab, always reset it to root
                if newValue == 0 {
                    homeNavigationPath = []
                } else if newValue == 1 {
                    libraryNavigationPath = []
                }
                self.selectedTab = newValue
            }
        )
    }
    
    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(libraryManager: libraryManager, selectedTab: $selectedTab, navigationPath: $homeNavigationPath)
                .tabItem {
                    Label("Now Playing", systemImage: "play.circle.fill")
                }
                .tag(0)
            
            LibraryView(libraryManager: libraryManager, navigationPath: $libraryNavigationPath)
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
        }
    }
}
