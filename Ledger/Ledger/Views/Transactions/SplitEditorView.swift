import SwiftUI
import SwiftData

/// Bloom split editor used inside the new / edit transaction sheet. Each split picks a category and
/// an amount, and can be removed with a small delete button since the editor no longer lives in a
/// `Form`/`List`.
struct SplitEditorView: View {
    var viewModel: TransactionEditViewModel
    let categories: [Category]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.splits) { split in
                HStack(spacing: 12) {
                    Menu {
                        Picker("Category", selection: binding(for: split).category) {
                            Text("Select category").tag(Category?.none)
                            ForEach(categories, id: \.persistentModelID) { category in
                                Text(category.name).tag(category as Category?)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(split.category?.name ?? "Select category")
                                .font(.appBody.weight(.semibold))
                                .foregroundStyle(Color.primary)
                            Image(systemName: "chevron.down")
                                .font(.appCaption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    TextField("0.00", text: binding(for: split).amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.appBody.weight(.heavy))
                        .frame(width: 90)

                    Button {
                        viewModel.removeSplit(split)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Palette.coral)
                            .font(.appTitle3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                viewModel.addSplit()
            } label: {
                Label("Add Split", systemImage: "plus.circle")
                    .font(.appBodyMedium.weight(.semibold))
                    .foregroundStyle(Palette.greenDeep)
            }
            .buttonStyle(.plain)

            if !viewModel.splits.isEmpty {
                HStack {
                    Text("Split total")
                        .font(.appCaption.weight(.bold))
                    Spacer()
                    Text(CurrencyFormatter.string(from: viewModel.splitTotal))
                        .font(.appCaption.weight(.black))
                        .foregroundStyle(viewModel.isSplitValid ? Color.secondary : Palette.expense)
                }
                .padding(.top, 4)
            }
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

#Preview {
    @Previewable @State var model: TransactionEditViewModel? = nil
    if let model {
        SplitEditorView(viewModel: model, categories: [])
    } else {
        Color.clear
    }
}
