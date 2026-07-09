import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CSVImportViewModel?
    @State private var isPresentingFileImporter = false

    private var allowedContentTypes: [UTType] {
        [
            .commaSeparatedText,
            .plainText,
            UTType(filenameExtension: "ofx") ?? .data,
            UTType(filenameExtension: "qfx") ?? .data
        ]
    }

    var body: some View {
        Group {
            if let viewModel {
                switch viewModel.stage {
                case .chooseFile:
                    chooseFileStage(viewModel)
                case .configure:
                    configureStage(viewModel)
                case .preview:
                    previewStage(viewModel)
                case .complete:
                    completeStage(viewModel)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isPresentingFileImporter, allowedContentTypes: allowedContentTypes) { result in
            switch result {
            case .success(let url):
                viewModel?.load(fileURL: url)
            case .failure(let error):
                viewModel?.fileSelectionFailed(error.localizedDescription)
            }
        }
        .task {
            if viewModel == nil { viewModel = CSVImportViewModel(modelContext: modelContext) }
        }
    }

    // MARK: - Stage: choose file

    private func chooseFileStage(_ viewModel: CSVImportViewModel) -> some View {
        VStack(spacing: 20) {
            if viewModel.accounts.isEmpty {
                EmptyStateView(
                    systemImage: "tray.and.arrow.down",
                    title: "Add an Account First",
                    message: "Imported transactions need an account to land in. Create one under Accounts, then come back."
                )
            } else {
                ContentUnavailableView {
                    Label("Import Transactions", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Import a CSV or OFX/QFX export from Wealthsimple or your bank. Transactions are deduplicated automatically.")
                } actions: {
                    Button {
                        isPresentingFileImporter = true
                    } label: {
                        Label("Choose File", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage: configure / map

    @ViewBuilder
    private func configureStage(_ viewModel: CSVImportViewModel) -> some View {
        Form {
            Section("File") {
                LabeledContent("File", value: viewModel.fileName ?? "—")
                LabeledContent("Format", value: viewModel.fileKind == .ofx ? "OFX / QFX" : "CSV")
            }

            Section("Import Into") {
                Picker("Account", selection: Binding(get: { viewModel.targetAccount }, set: { viewModel.targetAccount = $0 })) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.name).tag(Account?.some(account))
                    }
                }
            }

            if viewModel.fileKind == .csv {
                csvMappingSections(viewModel)
            } else {
                Section {
                    Text("This OFX file includes structured transaction data, so no column mapping is needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    viewModel.buildPreview()
                } label: {
                    Label("Preview Import", systemImage: "eye")
                }
                .disabled(!viewModel.canBuildPreview)
            }
        }
    }

    @ViewBuilder
    private func csvMappingSections(_ viewModel: CSVImportViewModel) -> some View {
        Section("Layout") {
            Toggle("First row is a header", isOn: Binding(get: { viewModel.hasHeaderRow }, set: { viewModel.hasHeaderRow = $0 }))
        }

        Section("Columns") {
            columnPicker("Date", selection: mappingBinding(viewModel, \.dateColumn), headers: viewModel.headers)
            columnPicker("Merchant", selection: mappingBinding(viewModel, \.merchantColumn), headers: viewModel.headers)

            Picker("Amount", selection: Binding(get: { viewModel.mapping.amountMode }, set: { viewModel.mapping.amountMode = $0 })) {
                ForEach(CSVColumnMapping.AmountMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            switch viewModel.mapping.amountMode {
            case .single:
                columnPicker("Amount column", selection: mappingBinding(viewModel, \.amountColumn), headers: viewModel.headers)
                Toggle("Positive means money out", isOn: Binding(
                    get: { viewModel.mapping.invertSingleAmountSign },
                    set: { viewModel.mapping.invertSingleAmountSign = $0 }
                ))
            case .separateInOut:
                columnPicker("Money out", selection: mappingBinding(viewModel, \.outflowColumn), headers: viewModel.headers)
                columnPicker("Money in", selection: mappingBinding(viewModel, \.inflowColumn), headers: viewModel.headers)
            }
        }

        Section("Date Format") {
            Picker("Format", selection: Binding(get: { viewModel.mapping.dateFormat }, set: { viewModel.mapping.dateFormat = $0 })) {
                ForEach(viewModel.availableDateFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int?>, headers: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag(Int?.none)
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                Text(header).tag(Int?.some(index))
            }
        }
    }

    private func mappingBinding(_ viewModel: CSVImportViewModel, _ keyPath: WritableKeyPath<CSVColumnMapping, Int?>) -> Binding<Int?> {
        Binding(
            get: { viewModel.mapping[keyPath: keyPath] },
            set: { viewModel.mapping[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Stage: preview

    @ViewBuilder
    private func previewStage(_ viewModel: CSVImportViewModel) -> some View {
        VStack(spacing: 0) {
            summaryBar(viewModel)
            List {
                ForEach(viewModel.previewRows) { row in
                    previewRow(row, viewModel: viewModel)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    viewModel.commit()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text(viewModel.newCount == 0 ? "Nothing New to Import" : "Import \(viewModel.newCount) Transaction\(viewModel.newCount == 1 ? "" : "s")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.newCount == 0)

                Button("Back to Mapping") { viewModel.backToConfigure() }
                    .font(.footnote)
            }
            .padding()
            .background(.bar)
        }
    }

    private func summaryBar(_ viewModel: CSVImportViewModel) -> some View {
        HStack(spacing: 16) {
            summaryChip(count: viewModel.newCount, label: "New", color: .green)
            summaryChip(count: viewModel.duplicateCount, label: "Duplicate", color: .secondary)
            if viewModel.errorCount > 0 {
                summaryChip(count: viewModel.errorCount, label: "Skipped", color: .orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        VStack {
            Text("\(count)").font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func previewRow(_ row: CSVImportViewModel.PreviewRow, viewModel: CSVImportViewModel) -> some View {
        if let transaction = row.transaction {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.merchant).fontWeight(.medium)
                    Text(DateFormatting.medium(transaction.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.currencyCode))
                        .foregroundStyle(transaction.amount < 0 ? .primary : .green)
                    if row.isDuplicate {
                        Text("Duplicate").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(row.isDuplicate ? 0.5 : 1)
        } else {
            Label(row.error ?? "Skipped row", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Stage: complete

    private func completeStage(_ viewModel: CSVImportViewModel) -> some View {
        ContentUnavailableView {
            Label("Import Complete", systemImage: "checkmark.circle.fill")
        } description: {
            if let summary = viewModel.summary {
                Text("\(summary.transactionsCreated) transactions imported, \(summary.transactionsSkipped) already present.")
            }
        } actions: {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    NavigationStack {
        CSVImportView()
    }
    .modelContainer(for: LedgerSchema.models, inMemory: true)
}
