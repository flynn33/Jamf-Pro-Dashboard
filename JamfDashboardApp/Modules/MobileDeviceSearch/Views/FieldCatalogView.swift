import SwiftUI

/// FieldCatalogView declaration.
struct FieldCatalogView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedFieldKeys: Set<String>
    let onSaveProfileRequested: () -> Void

    @State private var filterText = ""

    private var visibleFields: [MobileDeviceField] {
        guard filterText.isEmpty == false else {
            return MobileDeviceField.catalog
        }

        let query = filterText.localizedLowercase
        return MobileDeviceField.catalog.filter {
            $0.displayName.localizedLowercase.contains(query) ||
            $0.key.localizedLowercase.contains(query) ||
            $0.description.localizedLowercase.contains(query)
        }
    }

    private var allCatalogFieldKeys: Set<String> {
        Set(MobileDeviceField.catalog.map(\.key))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Select All Fields", isOn: selectAllFieldsBinding)
                }

                Section("Fields") {
                    ForEach(visibleFields) { field in
                        Toggle(isOn: toggleBinding(for: field.key)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(field.displayName)
                                    .font(.body)
                                Text(field.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .appInsetGroupedListStyle()
            .tint(BrandColors.bluePrimary)
            .searchable(text: $filterText, prompt: "Find field")
            .navigationTitle("Field Catalog")
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .appTopBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .appTopBarTrailing) {
                    Button("Save Profile") {
                        onSaveProfileRequested()
                    }
                    .disabled(selectedFieldKeys.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("\(selectedFieldKeys.count) selected")
                        .font(.caption)
                        .foregroundStyle(BrandColors.bluePrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .appBottomBarSurface()
            }
        }
    }

    /// Handles toggleBinding.
    private func toggleBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedFieldKeys.contains(key) },
            set: { isSelected in
                if isSelected {
                    selectedFieldKeys.insert(key)
                } else {
                    selectedFieldKeys.remove(key)
                }
            }
        )
    }

    /// Handles selectAllFieldsBinding.
    private var selectAllFieldsBinding: Binding<Bool> {
        Binding(
            get: {
                allCatalogFieldKeys.isEmpty == false &&
                allCatalogFieldKeys.isSubset(of: selectedFieldKeys)
            },
            set: { isSelected in
                if isSelected {
                    selectedFieldKeys.formUnion(allCatalogFieldKeys)
                } else {
                    selectedFieldKeys.subtract(allCatalogFieldKeys)
                }
            }
        )
    }
}

//endofline
