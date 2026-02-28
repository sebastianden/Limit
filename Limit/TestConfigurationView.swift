//
//  TestConfigurationView.swift
//  Limit
//
//  Pre-test configuration sheet for collecting hand and bodyweight data
//

import SwiftUI

struct TestConfigurationView: View {
    @Environment(\.dismiss) var dismiss

    @State private var selectedHand: Hand = .right
    @State private var bodyweightText: String = ""
    @State private var showBodyweightError: Bool = false

    let onStart: (Hand, Double) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hand", selection: $selectedHand) {
                        ForEach(Hand.allCases, id: \.self) { hand in
                            Label(hand.displayName, systemImage: hand.icon)
                                .tag(hand)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Which hand are you testing?")
                }

                Section {
                    HStack {
                        TextField("Enter bodyweight", text: $bodyweightText)
                            .keyboardType(.decimalPad)

                        Text("kg")
                            .foregroundStyle(.secondary)
                    }

                    if showBodyweightError {
                        Text("Please enter a valid bodyweight (20-300 kg)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Current Bodyweight")
                } footer: {
                    Text("Used to calculate relative values (CF/kg, W'/kg)")
                }
            }
            .navigationTitle("Test Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Test") {
                        startTest()
                    }
                    .fontWeight(.semibold)
                    .disabled(bodyweightText.isEmpty)
                }
            }
        }
    }

    private func startTest() {
        showBodyweightError = false

        // Parse and validate bodyweight
        guard let bodyweight = Double(bodyweightText), bodyweight >= 20 && bodyweight <= 300 else {
            showBodyweightError = true
            return
        }

        onStart(selectedHand, bodyweight)
        dismiss()
    }
}

#Preview {
    TestConfigurationView { hand, bodyweight in
        print("Starting test with hand: \(hand), bodyweight: \(bodyweight)")
    }
}
