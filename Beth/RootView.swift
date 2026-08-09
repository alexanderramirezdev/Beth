//
//  RootView.swift
//  Beth
//
//  A simple two-tab shell so the chat app and the research lab can
//  live side by side without either one editing the other.
//
//  This is deliberately the only new file that touches your working
//  ContentView, and it touches it by wrapping it, not by modifying it.
//

import SwiftUI

struct RootView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case chat = "Chat"
        case lab = "Action Lab"

        var id: String { rawValue }
    }

    @State private var tab: Tab = .chat

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 10)

            switch tab {
            case .chat:
                ContentView()
            case .lab:
                ActionLabView()
            }
        }
        .frame(minWidth: 620, minHeight: 700)
    }
}
