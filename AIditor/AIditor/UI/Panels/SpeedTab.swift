//
//  SpeedTab.swift
//  Projekt AIditor — UI/Panels
//
//  Fáze 18, modul 7. Záložka Rychlost připnutého panelu.
//
//  Konec 132bodového pásu: editor křivky dostal box 150 px v panelu širokém
//  452, a vedle sebe presety, čip segmentace, spotřebu zdroje, korekci výšky
//  a dopasování na hudbu. Dosud se všechno tohle muselo vejít pod přehrávač
//  vedle panelu barev — na křivku zbývalo 132 bodů výšky.
//

import AVFoundation
import SwiftUI
import TimelineModel

struct SpeedTab: View {
    @ObservedObject var timeline: TimelineController
    @ObservedObject var model: AppModel
    let clipID: ClipID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            presets
            editorBox
            segmentationRow
            pitchRow
            beatSection
        }
    }

    private var clip: Clip? { timeline.project.timeline.clip(clipID) }

    // MARK: - Rychlé presety

    /// Presety zpomalení. Pod mezí čistého zpomalení jsou **nedostupné
    /// a nesou důvod** — `pureSlowdownLimit` je `výstupFps / zdrojFps`
    /// a pod ním se snímky duplikují. Ruční cesta přes žlutou zónu editoru
    /// zůstává; automatika mez nepřekračuje.
    private var presets: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("Rychlost")
            HStack(spacing: 6) {
                presetButton(title: "Bez rampy", speed: nil)
                ForEach([0.5, 0.25, 0.125], id: \.self) { speed in
                    presetButton(title: Self.speedLabel(speed), speed: speed)
                }
            }
        }
    }

    /// ⚠️ **Tolerance 2 % na mez čistého zpomalení, a je to úmysl.**
    ///
    /// `pureSlowdownLimit` je `výstupFps / zdrojFps` z NAMĚŘENÉ frekvence.
    /// Testovací klipy mají 59,68 fps, takže mez vyjde 0,5027 — a preset
    /// „0,5×" by byl trvale nedostupný kvůli propadu 0,54 %, tedy asi jednomu
    /// duplikovanému snímku z dvou set. To by z celé řady presetů udělalo
    /// ozdobu na každém 60fps materiálu (a ten je podle měření většinový).
    ///
    /// Editor křivky si žlutou zónu kreslí dál PŘESNĚ podle meze — tolerance
    /// platí jen pro presety, kde je rozdíl řádu jednoho snímku neslyšitelný
    /// a alternativou je funkce, kterou nikdo nikdy nezmáčkne.
    static let presetLimitTolerance = 0.02

    private func presetButton(title: String, speed: Double?) -> some View {
        let limit = clip.flatMap { timeline.project.pureSlowdownLimit(of: $0) }
        let belowLimit = speed.map { limit != nil
            && $0 < limit! * (1 - Self.presetLimitTolerance) } ?? false
        let isActive = speed == nil
            ? clip?.speedRamp == nil
            : abs((clip?.speedRamp?.nodes.map(\.speed).min() ?? -1) - speed!) < 1e-6

        return Button {
            timeline.setClassicRamp(clipID, slowSpeed: speed)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? AIditorUI.accent
                                 : (belowLimit ? AIditorUI.textDisabled : AIditorUI.textPrimary))
                .frame(maxWidth: .infinity)
                .frame(height: AIditorUI.Metric.controlHeight)
                .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                    .fill(isActive ? Color(aiditorHex: 0x3A3320) : AIditorUI.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                    .strokeBorder(isActive ? AIditorUI.accent : AIditorUI.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // ⚠️ Aktivní preset se NEVYPÍNÁ, i když je pod mezí. Klip takovou
        // rampu mít může (nastaví ji kontextové menu nebo ruční editor přes
        // žlutou zónu) a šedivět STAV, který právě platí, uživatele mate —
        // vypadá to jako chyba kreslení. Vypnutá je jen volba, kterou by
        // teprve zvolil. Chyceno screenshotem, ne měřením.
        .disabled(belowLimit && !isActive)
        .help(belowLimit
              ? "Zdroj má \(Self.sourceFPSText(clip, project: timeline.project)) — čisté zpomalení "
                + "končí na \(Self.speedLabel(limit ?? 0)). Pod tím se snímky duplikují; "
                + "ručně to jde v editoru křivky, přiznaně přes žlutou zónu."
              : (speed == nil ? "Klip pojede 1×." : "Zpomalení \(title) s náběhem a dojezdem."))
    }

    // MARK: - Editor křivky

    private var editorBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            RampEditorPaneView(controller: timeline)
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 8).fill(AIditorUI.surfaceWindow))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(AIditorUI.border, lineWidth: 1))
            Text("dvojklik přidá uzel · Delete smaže · Shift vypne přichytávání")
                .font(AIditorUI.Font.chip)
                .foregroundStyle(AIditorUI.textTertiary)
        }
    }

    // MARK: - Segmentace a spotřeba

    /// Čip segmentace a spotřeba zdroje. Obojí je odvozené z modelu, ne
    /// z UI — segmentaci počítá `rampPlaybackPlan`, spotřebu
    /// `sourceConsumption`. Bez rampy nemá čip co říct, takže není.
    private var segmentationRow: some View {
        HStack(spacing: 8) {
            if let clip, clip.speedRamp != nil,
               let plan = timeline.project.rampPlaybackPlan(of: clip) {
                chip("\(plan.segments.count) úseků", color: AIditorUI.accent)
                if plan.limitedByFrameRate {
                    chip("mez skoku nedosažitelná", color: AIditorUI.warn)
                }
            }
            if let clip {
                Text("spotřeba zdroje "
                     + String(format: "%.3f s", timeline.project.sourceConsumption(of: clip).seconds))
                    .font(AIditorUI.Font.chip)
                    .foregroundStyle(AIditorUI.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Korekce výšky

    private var pitchRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("Korekce výšky")
            Picker("", selection: Binding(
                get: { model.pitchAlgorithm },
                set: { model.pitchAlgorithm = $0 })) {
                Text("Časová doména").tag(AVAudioTimePitchAlgorithm.timeDomain)
                Text("Spektrální").tag(AVAudioTimePitchAlgorithm.spectral)
                Text("Bez korekce (výška jde s rychlostí)")
                    .tag(AVAudioTimePitchAlgorithm.varispeed)
            }
            .labelsHidden()
            .controlSize(.small)
            .help("Časová doména zachovává transienty (rána sekerou zůstane rána). "
                  + "Spektrální je fázový vokodér — na drženém tónu lepší, na transientech "
                  + "plechový. ⚠️ Platí na celý film: je to vlastnost přehrávaného itemu, "
                  + "ne klipu.")
        }
    }

    // MARK: - Dopasování na hudbu

    /// Dvě operace z fáze 14, modulu 3. O dostupnosti rozhoduje **zkušební
    /// běh na kopii projektu** — panel nelže: vypnutá položka nese důvod
    /// z chyby modelu, ne obecné „nejde to".
    private var beatSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle("Dopasování na hudbu")

            let rampProbe = probe { _ = try $0.rampClipToBeat(clipID: clipID,
                                                              near: timeline.playhead) }
            let fitProbe = probe { _ = try $0.fitClipEndToBeat(clipID: clipID) }

            beatButton(title: "Zpomalení na dobu", failure: rampProbe) {
                timeline.rampClipToBeat(clipID)
            }
            beatButton(title: "Zarovnat konec na dobu", failure: fitProbe) {
                timeline.fitClipEndToBeat(clipID)
            }

            if let nearest = nearestBeatText {
                Text(nearest)
                    .font(AIditorUI.Font.chip)
                    .foregroundStyle(AIditorUI.textTertiary)
            }
        }
    }

    /// Zkušební běh na KOPII. Vrací chybu, když operace neprojde.
    private func probe(_ body: (inout Project) throws -> Void) -> TimelineError? {
        var copy = timeline.project
        do {
            try body(&copy)
            return nil
        } catch let error as TimelineError {
            return error
        } catch {
            // Neznámá chyba: položka se stejně vypne, ale rada zůstane
            // obecná — vymýšlet konkrétní důvod k chybě, kterou neznám,
            // by bylo horší než přiznat, že to nejde.
            return .clipNotFound(clipID)
        }
    }

    private func beatButton(title: String, failure: TimelineError?,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AIditorUI.Font.control)
                .foregroundStyle(failure == nil ? AIditorUI.textPrimary : AIditorUI.textDisabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: AIditorUI.Metric.controlHeight)
                .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                    .fill(AIditorUI.surfaceControl))
                .overlay(RoundedRectangle(cornerRadius: AIditorUI.Metric.controlRadius)
                    .strokeBorder(AIditorUI.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(failure != nil)
        .help(failure?.beatFitReason(frameRate: timeline.project.timeline.frameRate)
              ?? "Provede se jedním undo krokem.")
    }

    private var nearestBeatText: String? {
        guard case .noBeatInReach(let nearest)? = probe({ _ = try $0.fitClipEndToBeat(clipID: clipID) }),
              let nearest else { return nil }
        let rate = timeline.project.timeline.frameRate
        return "Nejbližší doba na \(nearest.timecode(frameRate: rate).text)."
    }

    // MARK: - Drobnosti

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AIditorUI.Font.sectionTitle)
            .tracking(0.7)
            .foregroundStyle(AIditorUI.textTertiary)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AIditorUI.Font.chip)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: AIditorUI.Metric.chipRadius)
                .fill(color.opacity(0.12)))
    }

    /// „0,25×" česky — desetinná čárka, ne tečka.
    ///
    /// Nejvýš tři desetinná místa a bez koncových nul: `%g` dělalo z meze
    /// čistého zpomalení „0,502667×", což je číslo, které nikdo nečte
    /// (chyceno screenshotem záložky Info).
    static func speedLabel(_ speed: Double) -> String {
        var text = String(format: "%.3f", speed)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: ".", with: ",") + "×"
    }

    private static func sourceFPSText(_ clip: Clip?, project: Project) -> String {
        guard let clip, let asset = project.asset(clip.assetID) else { return "neznámou frekvenci" }
        return String(format: "%.0f fps", asset.measuredFrameRate)
    }
}

// MARK: - Důvody, proč dopasování nejde

/// Překlad chyby modelu do rady pro uživatele.
///
/// **Jediné místo.** Dřív tuhle tabulku měl `TimelineDocumentView` u svého
/// kontextového menu; od fáze 18 ji čte i panel a dvě kopie téhož textu by
/// se rozešly, jakmile v modelu přibude případ.
extension TimelineError {
    /// `frameRate` se předává, neodhaduje — timecode v radě musí být v téže
    /// základně jako pravítko, jinak rada posílá uživatele na jiné místo.
    func beatFitReason(frameRate: Int) -> String {
        switch self {
        case .noBeatInReach(let nearest):
            if let nearest {
                return "V dosahu není volná doba — nejbližší je na "
                    + "\(nearest.timecode(frameRate: frameRate).text). "
                    + "Trimni klip, posuň ho, nebo přisuň hudbu."
            }
            return "Na ose není hudba s dobami — přidej ji přes Soubor → Přidat hudbu…"
        case .noCleanSlowdown:
            return "Zdroj nemá dost snímků na čisté zpomalení "
                + "(potřeba zdrojFps ≥ výstupFps/rychlost). Ručně to jde "
                + "v editoru křivky — přiznaně, přes žlutou zónu."
        case .blockedByTransition:
            return "Na střihu klipu leží přechod — napřed ho odeber."
        case .beatFitOnMusicClip:
            return "Tohle je hudební klip — dopasovávají se záběry na něj, "
                + "ne on sám na sebe."
        case .rampOnStillClip:
            return "Fotka rampu nedostane — freeze frame se dělá fotkou."
        default:
            return "Dopasování tady nejde provést."
        }
    }
}
