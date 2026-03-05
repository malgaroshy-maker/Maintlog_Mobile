# MaintLog Pro

MaintLog Pro is a comprehensive, modern maintenance logging and management application designed specifically for industrial and manufacturing environments. Built with Flutter and powered by Supabase, it provides a seamless experience across devices to track production downtime, manage spare parts inventory, and coordinate engineering crews.

## Key Features

- **Maintenance Logbook:** Record downtime events, track work descriptions, and detail parts used. Supports multiple shifts, precise downtime calculators, and historical tracking.
- **Smart AI Assistant:** Features an integrated AI assistant powered by Google Gemini (supporting Gemini 2.5 and 3.0 models). The assistant can analyze logbook entries, answer maintenance questions, and even read attached images or manuals via multi-modal support.
- **Real-time Dashboard:** A dynamic analytics dashboard with date-range filtering, displaying vital KPIs such as total machine downtime, open tasks, shift breakdowns, and low stock alerts.
- **Inventory Management:** Full CRUD capabilities for spare parts, complete with low stock warnings and live inventory tracking.
- **Engineering Coordination:** Manage engineering crews, assign roles, define active shifts, and track who completed which maintenance tasks.
- **Offline-First Synchronization:** Engineered with a robust local SQLite database and a sophisticated background sync engine to ensure seamless operation regardless of network connectivity. All data points (logs, tasks, parts, machines) are actively synced to Supabase when a connection is available.

## Technologies Used

- **Frontend:** Flutter & Dart
- **Backend & Authentication:** Supabase
- **Local Database:** sqflite (SQLite)
- **AI Integration:** Google Generative AI (Gemini)
- **State Management:** Provider

## Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable version)
- A Supabase Project (with properly configured tables: `log_entries`, `todo_tasks`, `spare_parts`, `machines`, `engineers`, `shift_engineers`, `line_numbers`)
- A Google Gemini API Key

### Installation

1. **Clone the repository:**
   ```bash
   git clone <repository_url>
   cd MaintlogAi/maintlog_app
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Environment:**
   Update the Supabase URL and Anon Key within `lib/main.dart` or via a `.env` file (if configured). Users can set their Gemini API key directly within the app's settings menu.

4. **Run the application:**
   ```bash
   flutter run
   ```

## Developer Information

Developed and maintained by **Mahamed Algaroshy**.

**Contact:** [Malgaroshy@gmail.com](mailto:Malgaroshy@gmail.com)

## License
This project is proprietary and confidential. Unauthorized copying or distribution of this file, via any medium, is strictly prohibited.
