//
//  ContentView.swift
//  BookReader
//
//  Created by Dave Marvit on 1/25/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var libraryManager: LibraryManager
    
    var body: some View {
        TabView {
            HomeView(libraryManager: libraryManager)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            LibraryView(libraryManager: libraryManager)
                .tabItem {
                    Label("Library", systemImage: "books.vertical.fill")
                }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
