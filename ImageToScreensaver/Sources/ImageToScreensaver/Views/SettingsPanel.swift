import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        Form {
            Section("Slideshow") {
                LabeledContent("Duration per image") {
                    HStack {
                        Slider(value: $vm.config.duration, in: 1...30, step: 0.5)
                            .frame(maxWidth: 180)
                        Text(String(format: "%.1f s", vm.config.duration))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Picker("Transition", selection: $vm.config.transition) {
                    ForEach(TransitionEffect.allCases) { Text($0.displayName).tag($0) }
                }
                if vm.config.transition != .none {
                    LabeledContent("Transition length") {
                        HStack {
                            Slider(value: $vm.config.transitionDuration, in: 0.1...3.0, step: 0.1)
                                .frame(maxWidth: 180)
                            Text(String(format: "%.1f s", vm.config.transitionDuration))
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
                Toggle("Shuffle order", isOn: $vm.config.shuffle)
            }

            Section("Display") {
                Picker("Fit mode", selection: $vm.config.fitMode) {
                    ForEach(FitMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Target resolution", selection: $vm.config.resolution) {
                    ForEach(Resolution.presets) { Text($0.label).tag($0) }
                }
                ColorPickerField(hex: $vm.config.backgroundColor)
            }

            Section("Output") {
                TextField("Filename", text: $vm.config.outputFilename)
                Text("Will be saved as \(vm.config.outputFilename).scr")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ColorPickerField: View {
    @Binding var hex: String
    @State private var color: Color = .black

    var body: some View {
        HStack {
            Text("Background")
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _, newValue in
                    hex = newValue.toHexString()
                }
        }
        .onAppear { color = Color(hex: hex) ?? .black }
    }
}

private extension Color {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255.0,
                  green: Double((v >> 8) & 0xff) / 255.0,
                  blue: Double(v & 0xff) / 255.0)
    }
    func toHexString() -> String {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
