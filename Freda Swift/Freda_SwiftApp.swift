//
//  Freda_SwiftApp.swift
//  Freda Swift
//
//  Created by Hakan Tapanyiğit on 1.02.2025.
//

import SwiftUI

@main
struct Freda_SwiftApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
