# InventoryAI (ProjectVay)

InventoryAI is a monorepo for a local-first iOS home inventory application featuring AI-powered meal planning and recipe management.

## Project Structure

*   **`ios/`**: SwiftUI iPhone application (Client).
*   **`backend/`**: Node.js/TypeScript Express API (Stateless Intelligence).
*   **`docs/`**: Comprehensive architectural documentation and specifications.
*   **`ownyourcode/`**: Mentorship and learning tracking artifacts.

## Architecture

### iOS App (Client)
*   **Framework**: SwiftUI, Combine.
*   **Architecture**: MVVM (Features → Services → Repositories → Persistence).
*   **Database**: SQLite via **GRDB.swift**. Fully local-first; inventory data never leaves the device.
*   **Dependency Injection**: Services are injected via `AppDependencies` into the SwiftUI Environment.
*   **Key Libraries**: Nuke (Image Loading), VisionKit (Barcode Scanning).
*   **Scanning**: `DataScannerViewController` for EAN-13 and DataMatrix codes with a robust lookup pipeline (Local -> External Providers -> Fallback).

### Backend (API)
*   **Runtime**: Node.js, TypeScript.
*   **Framework**: Express.js.
*   **Purpose**: Stateless API for recipe search, recommendation, and meal plan generation.
*   **Data**:
    *   **Recipe Index**: In-memory search index + SQLite persistent cache (`persistentRecipeCache`).
    *   **Scraper**: Fetches and parses schema.org JSON-LD from whitelisted recipe sources.
*   **Endpoints**:
    *   `/recipes/fetch`: Scrape and cache recipes.
    *   `/recipes/recommend`: Rank recipes based on inventory, expiry, and macros.
    *   `/meal-plan/generate`: Generate 1-7 day meal plans.

## Development Workflows

### iOS Development
*   **Project Management**: Uses **XcodeGen**. The canonical definition is `ios/project.yml`.
    *   Regenerate project: `cd ios && xcodegen generate`
    *   **Note**: Do not manually modify the `.xcodeproj` file structure; update `project.yml` instead.
*   **IDE**: Xcode 16.2+.
*   **Tests**: `InventoryCoreTests` scheme covers models, services, and use cases.
    *   Run tests: `xcodebuild -project ios/InventoryAI.xcodeproj -scheme InventoryCore test`

### Backend Development
*   **Setup**: `cd backend && npm ci`
*   **Run (Dev)**: `npm run dev` (Watch mode on port 8080).
*   **Testing**:
    *   Unit/Integration: `npm test` (Node test runner).
    *   Coverage: `npm run test:coverage` (Vitest).
*   **Docker**: `docker-compose up backend` for a production-like environment.

## Key Features & Logic

1.  **Local-First Privacy**:
    *   Inventory (Products, Batches, Prices) is stored in the iOS local SQLite DB.
    *   Only anonymous barcode lookups and meal plan requests (with ingredient lists, not user identity) are sent to the backend.

2.  **Smart Expiry Notifications**:
    *   Notifications are scheduled locally based on "Quiet Hours" defined in settings.
    *   Logic handles rescheduling when settings change.

3.  **Meal Planning**:
    *   **Input**: Local inventory + Dietary Goals (from Apple Health/Yazio) + Constraints (Budget, Dislikes).
    *   **Process**: Backend generates a plan optimizing for:
        *   Using up expiring items.
        *   Hitting macro targets (Protein/Carbs/Fat).
        *   Minimizing cost.
        *   Generating "better under macros" alternatives even if missing ingredients.

4.  **Shopping List**:
    *   Fully integrated locally with automatic generation from missing recipe ingredients.
    *   Manual addition and smart "Check-off" scanning mode to instantly mark items as purchased in-store.

## Conventions

*   **Language**: Always communicate with the user in Russian.
    *   **Code**: English (Variables, Comments, Commits).
    *   **UI/Data**: Russian (Product names, Interface strings).
*   **Migrations**: Database changes (GRDB) are additive and versioned in `ios/Persistence/Migrations.swift`.
*   **Security**:
    *   Strict `recipeSources` whitelist in backend.
    *   Rate limiting on all API endpoints.

## AI Agent Guidelines (OwnYourCode)

This workspace follows the "OwnYourCode" mentorship protocol. When acting as an AI assistant:
1.  **CRITICAL RULE**: ALWAYS communicate with the user in Russian. No exceptions.
2.  **Mentor, Don't Soliver**: Do not write full solutions. Provide guidance, patterns (max 8 lines of code), and questions.
3.  **Verify Understanding**: Before moving on, ensure the user understands the *why* and *how*. Ask: "Walk me through this code."
4.  **Documentation First**: Encourage checking official docs (Context7) before providing answers.
5.  **Protocol D**: When debugging, guide the user through Reading, Isolating, Hypothesizing, and Verifying.
6.  **6 Gates**: Ensure code passes gates for Ownership, Security, Error Handling, Performance, Fundamentals, and Testing.

## Workflow Orchestration

### 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately – don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes – don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, point at failing tests – then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management
1. **Plan First**: Write plan to `task.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `walkthrough.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimat Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
