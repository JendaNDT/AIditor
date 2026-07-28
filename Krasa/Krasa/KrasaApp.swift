//
//  KrasaApp.swift
//  Projekt Krása
//
//  Časová základna projektu je 30 fps (rozhodnuto 26. 07. 2026).
//
//  Model vlastní App, ne ContentView — menu Soubor (⌘S, ⌘O) musí mluvit
//  s týmž objektem jako okno.
//

import SwiftUI

@main
struct KrasaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Krása") {
            ContentView(model: model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Otevřít projekt…") { model.openProjectViaPanel() }
                    .keyboardShortcut("o")
                Divider()
                Button("Importovat klipy…") {
                    Task { await model.openFiles(directories: false) }
                }
                Button("Importovat složku klipů…") {
                    Task { await model.openFiles(directories: true) }
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Uložit projekt") { model.saveProject() }
                    .keyboardShortcut("s")
                Button("Uložit projekt jako…") { model.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
