import SwiftUI

struct RecipeSearchSheet: View {
    let recipeServiceClient: RecipeServiceClient?

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Recipe] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?

    private let localCatalog = LocalRecipeCatalog()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty && !query.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .background(Color.vayBackground)
            .navigationTitle("Поиск рецептов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .onAppear {
            results = localCatalog.recipes.prefix(20).map { $0 }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: VaySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Название рецепта или ингредиент…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newValue in
                    scheduleSearch(query: newValue)
                }
        }
        .padding(VaySpacing.sm)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .padding(.horizontal, VaySpacing.lg)
        .padding(.vertical, VaySpacing.sm)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: VaySpacing.md) {
            Image(systemName: "fork.knife.circle")
                .font(VayFont.hero(44))
                .foregroundStyle(.tertiary)
            Text("Рецепты не найдены")
                .font(VayFont.heading(16))
            Text("Попробуйте другой запрос")
                .font(VayFont.body(14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: VaySpacing.sm) {
                ForEach(results) { recipe in
                    recipeRow(recipe)
                }
            }
            .padding(.horizontal, VaySpacing.lg)
            .padding(.bottom, VaySpacing.xl)
        }
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: VaySpacing.sm) {
            HStack(spacing: VaySpacing.md) {
                VStack(alignment: .leading, spacing: VaySpacing.xs) {
                    Text(recipe.title)
                        .font(VayFont.label(15))
                        .lineLimit(2)
                    HStack(spacing: VaySpacing.sm) {
                        Label("\(recipe.totalTimeMinutes ?? 0) мин", systemImage: "clock")
                            .font(VayFont.caption(12))
                            .foregroundStyle(.secondary)
                        if let kcal = recipe.nutrition?.kcal {
                            Label("\(Int(kcal)) ккал", systemImage: "flame.fill")
                                .font(VayFont.caption(12))
                                .foregroundStyle(Color.vayCalories)
                        }
                    }
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(VayFont.heading(22))
                    .foregroundStyle(Color.vayPrimary)
            }
        }
        .padding(VaySpacing.md)
        .background(Color.vayCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: VayRadius.md, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            dismiss()
        }
    }

    // MARK: - Search Logic

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            results = localCatalog.recipes.prefix(20).map { $0 }
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    @MainActor
    private func performSearch(query: String) async {
        isLoading = true
        defer { isLoading = false }

        if let client = recipeServiceClient {
            let serverResults = try? await client.search(query: query)
            if let serverResults, !serverResults.isEmpty {
                results = serverResults
                return
            }
        }

        results = localCatalog.search(query: query, limit: 30)
    }
}
