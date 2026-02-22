//
//  PersistenceManager.swift
//  Limit
//
//  Handles saving and loading test results
//

import Foundation
import Combine

class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    @Published var testResults: [TestResult] = []

    private let fileName = "test_results.json"

    private var fileURL: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent(fileName)
    }

    init() {
        loadResults()
    }

    // MARK: - Save & Load

    func save(result: TestResult) {
        testResults.insert(result, at: 0) // Add to beginning (most recent first)
        saveResults()
    }

    func delete(result: TestResult) {
        testResults.removeAll { $0.id == result.id }
        saveResults()
    }

    func deleteAll() {
        testResults.removeAll()
        saveResults()
    }

    private func saveResults() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(testResults)
            try data.write(to: fileURL, options: [.atomic])
            print("✅ Saved \(testResults.count) test results")
        } catch {
            print("❌ Error saving results: \(error)")
        }
    }

    private func loadResults() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("ℹ️ No saved results file found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            testResults = try decoder.decode([TestResult].self, from: data)
            print("✅ Loaded \(testResults.count) test results")
        } catch {
            print("❌ Error loading results: \(error)")
        }
    }

    // MARK: - Export

    func exportToCSV(result: TestResult) -> URL? {
        let csv = result.toCSV()

        let tempDirectory = FileManager.default.temporaryDirectory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: result.date)
        let fileName = "CF_Test_\(dateString).csv"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Exported CSV to: \(fileURL)")
            return fileURL
        } catch {
            print("❌ Error exporting CSV: \(error)")
            return nil
        }
    }
}
