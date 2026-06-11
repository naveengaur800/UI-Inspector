//
//  View_DrawingApp.swift
//  View Drawing
//
//  Created by Naveen Gaur on 10/6/2026.
//

import DesignReviewKit
import SwiftUI

@main
struct View_DrawingApp: App {

    /// Composition root owns the inspector; views reach it via the environment.
    @State
    private var inspector = DesignInspector()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .designInspector(inspector)
        }
    }
}
