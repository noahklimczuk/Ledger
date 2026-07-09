import SwiftUI

struct SplitEditorView: View {
    var viewModel: TransactionEditViewModel
    let categories: [Category]

    var body: some View {
        ForEach(viewModel.splits) { split in
            HStack {
                Picker("Category", selection: binding(for: split).category) {
                    Text("Select category").tag(Category?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Category?.some(category))
                    }
                }
                .labelsHidden()
                TextField("0.00", text: binding(for: split).amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
            }
        }
        .onDelete { indexSet in
            for index in indexSet {
                viewModel.removeSplit(viewModel.splits[index])
            }
        }

        Button {
            viewModel.addSplit()
        } label: {
            Label("Add Split", systemImage: "plus.circle")
        }

        if !viewModel.splits.isEmpty {
            HStack {
                Text("Split total")
                Spacer()
                Text(CurrencyFormatter.string(from: viewModel.splitTotal))
                    .foregroundStyle(viewModel.isSplitValid ? Color.secondary : Color.red)
            }
            .font(.footnote)
        }
    }

    private func binding(for split: TransactionEditViewModel.SplitDraft) -> SplitBinding {
        SplitBinding(viewModel: viewModel, splitId: split.id)
    }
}

private struct SplitBinding {
    let viewModel: TransactionEditViewModel
    let splitId: UUID

    var category: Binding<Category?> {
        Binding(
            get: { viewModel.splits.first { $0.id == splitId }?.category },
            set: { newValue in
                if let index = viewModel.splits.firstIndex(where: { $0.id == splitId }) {
                    viewModel.splits[index].category = newValue
                }
            }
        )
    }

    var amountText: Binding<String> {
        Binding(
            get: { viewModel.splits.first { $0.id == splitId }?.amountText ?? "" },
            set: { newValue in
                if let index = viewModel.splits.firstIndex(where: { $0.id == splitId }) {
                    viewModel.splits[index].amountText = newValue
                }
            }
        )
    }
}
