//
//  BethApp.swift
//  Beth
//
//  ENTRY POINT. The @main attribute tells Swift the program starts here.
//

import SwiftUI

@main
struct BethApp: App {

    // One shared coordinator for the chat side, passed down to any
    // view that needs it. The Action Lab owns its own separate state,
    // because it is a different experiment with different lifetimes.
    @State private var viewModel = BethViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(viewModel)
        }
        .defaultSize(width: 700, height: 820)
    }
}
