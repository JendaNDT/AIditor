//
//  KrasaApp.swift
//  Projekt Krása
//
//  Fáze 1 — kostra, import, přehrávač, měření náhledu.
//  Časová základna projektu je 30 fps (rozhodnuto 26. 07. 2026).
//

import SwiftUI

@main
struct KrasaApp: App {
    var body: some Scene {
        WindowGroup("Krása") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
