//
//  KrasaApp.swift
//  Projekt Krása
//
//  Časová základna projektu je 30 fps (rozhodnuto 26. 07. 2026).
//
//  Model vlastní App, ne ContentView — menu Soubor (⌘S, ⌘O) musí mluvit
//  s týmž objektem jako okno.
//

import AppKit
import SwiftUI

/// Delegát kvůli ⌘Q s neuloženými změnami — SwiftUI vlastní hák na „zeptej
/// se před ukončením" nemá, `applicationShouldTerminate` ho má. Model se
/// přišívá v `onAppear`, delegáta vyrábí SwiftUI dřív než `@StateObject`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (model?.shouldTerminate() ?? true) ? .terminateNow : .terminateCancel
    }
}

@main
struct KrasaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Krása") {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
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
                Divider()
                // Fotky se PŘIDÁVAJÍ do rozdělané práce (fáze 12) —
                // import klipů výše naproti tomu staví osu znovu.
                Button("Přidat fotky…") { model.addPhotos() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Uložit projekt") { model.saveProject() }
                    .keyboardShortcut("s")
                Button("Uložit projekt jako…") { model.saveProjectAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Exportovat film…") { model.exportMovie() }
                    .keyboardShortcut("e")
                Button("Exportovat titulky (.srt)…") { model.exportSubtitles() }
            }
        }
    }
}
