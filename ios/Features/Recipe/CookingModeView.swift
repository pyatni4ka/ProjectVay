import SwiftUI

struct CookingModeView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStepIndex = 0
    @State private var isShowingIngredients = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isShowingIngredients {
                    ingredientsView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if recipe.instructions.isEmpty {
                    emptyStepsView
                } else {
                    stepByStepView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .vayAccessibilityLabel("Закрыть режим готовки")
                }
                
                ToolbarItem(placement: .principal) {
                    Text(recipe.title)
                        .font(VayFont.heading(16))
                        .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        withAnimation(VayAnimation.springSnappy) {
                            isShowingIngredients.toggle()
                        }
                    }) {
                        Image(systemName: isShowingIngredients ? "list.bullet.circle.fill" : "list.bullet.circle")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    .vayAccessibilityLabel(isShowingIngredients ? "Закрыть ингредиенты" : "Показать ингредиенты")
                }
            }
        }
        .onAppear {
            // Prevent screen from sleeping while cooking
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    // MARK: - Step-by-Step View
    
    private var stepByStepView: some View {
        VStack(spacing: 0) {
            // Main content area
            TabView(selection: $currentStepIndex) {
                ForEach(0..<recipe.instructions.count, id: \.self) { index in
                    VStack(spacing: VaySpacing.xl) {
                        Text("ШАГ \(index + 1) ИЗ \(recipe.instructions.count)")
                            .font(VayFont.label(14).weight(.bold))
                            .foregroundStyle(Color.vayPrimary)
                            .padding(.top, VaySpacing.xl)
                        
                        ScrollView {
                            Text(recipe.instructions[index])
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(8)
                                .padding(.horizontal, VaySpacing.xl)
                                .padding(.vertical, VaySpacing.xxl)
                        }
                        
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(VayAnimation.springBounce, value: currentStepIndex)
            
            // Bottom controls
            VStack(spacing: VaySpacing.lg) {
                HStack(spacing: VaySpacing.xl) {
                    Button(action: {
                        withAnimation {
                            if currentStepIndex > 0 { currentStepIndex -= 1 }
                        }
                    }) {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(currentStepIndex > 0 ? .white : .white.opacity(0.3))
                    }
                    .disabled(currentStepIndex == 0)
                    .vayAccessibilityLabel("Предыдущий шаг")
                    
                    Text("\(currentStepIndex + 1) / \(recipe.instructions.count)")
                        .font(VayFont.heading(18))
                        .foregroundStyle(.white)
                        .frame(width: 80)
                    
                    Button(action: {
                        withAnimation {
                            if currentStepIndex < recipe.instructions.count - 1 {
                                currentStepIndex += 1
                            } else {
                                // Final step action (e.g., mark as done)
                                dismiss()
                            }
                        }
                    }) {
                        Image(systemName: currentStepIndex < recipe.instructions.count - 1 ? "chevron.right.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(currentStepIndex < recipe.instructions.count - 1 ? .white : Color.vaySuccess)
                    }
                    .vayAccessibilityLabel(currentStepIndex < recipe.instructions.count - 1 ? "Следующий шаг" : "Завершить")
                }
                .padding(.bottom, VaySpacing.xl)
            }
        }
    }
    
    // MARK: - Ingredients View
    
    private var ingredientsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ингредиенты")
                .font(VayFont.title(28))
                .foregroundStyle(.white)
                .padding()
                .padding(.top, VaySpacing.lg)
            
            ScrollView {
                VStack(alignment: .leading, spacing: VaySpacing.md) {
                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        HStack(alignment: .top) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.vayPrimary)
                                .padding(.top, 8)
                            
                            Text(ingredient)
                                .font(VayFont.body(18))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.vertical, 4)
                        
                        Divider()
                            .background(.white.opacity(0.2))
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStepsView: some View {
        VStack(spacing: VaySpacing.md) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.5))
            
            Text("Нет инструкций")
                .font(VayFont.heading(20))
                .foregroundStyle(.white)
            
            Text("Для этого рецепта не указаны пошаговые инструкции.")
                .font(VayFont.body(16))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Закрыть") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vayPrimary)
            .padding(.top, VaySpacing.lg)
        }
    }
}
