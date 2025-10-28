//
//  ContentView.swift
//  LucidBannerDemo
//
//  Created by Marino Faggiana on 28/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Show Top Banner") {
                let token = LucidBanner.shared.show(
                    title: "Upload started",
                    subtitle: "Keep the app in foreground",
                    systemImage: "arrowshape.up.circle",
                    imageAnimation: .breathe,
                    vPosition: .top,
                    autoDismissAfter: 2.0
                ) { state in
                    ToastBannerView(state: state)
                }
                _ = token
            }

            Button("Show Bottom Banner") {
                _ = LucidBanner.shared.show(
                    title: "All done",
                    systemImage: "checkmark.circle",
                    vPosition: .bottom,
                    autoDismissAfter: 2.0
                ) { state in
                    ToastBannerView(state: state)
                }
            }
        }
        .padding()
    }
}
