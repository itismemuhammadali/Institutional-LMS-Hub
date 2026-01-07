# Institutional LMS/CMS Hub

A Flutter-based student portal application with role-based access control for educational institutions. This project provides a comprehensive learning management system with support for students, teachers, and administrators.

## Features

- **Role-Based Access Control**: Different interfaces and permissions for students, teachers, and admins
- **Student Portal**: View grades, assignments, attendance, and class schedules
- **Teacher Dashboard**: Manage classes, grades, and student information
- **Admin Panel**: Institutional management and user administration
- **Real-time Chat**: Communication between students and teachers
- **File Management**: Upload and download educational materials
- **Responsive Design**: Works on mobile, tablet, and web platforms

## Project Structure

```
├── lib/                    # Flutter application source code
├── backend/               # PHP backend API
│   ├── api.php           # Main API endpoints
│   ├── chat_api.php      # Chat functionality
│   ├── database_setup.sql # Database initialization
│   └── ...
├── android/              # Android native code
├── ios/                  # iOS native code
├── web/                  # Web platform code
├── assets/               # Images and static assets
└── pubspec.yaml         # Flutter dependencies
```

## Prerequisites

- Flutter SDK (>=3.19.0)
- Dart SDK (^3.3.0)
- PHP 7.4+ (for backend)
- MySQL/MariaDB (for database)

## Getting Started

### Frontend Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd institutional_lms_cms_hub
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the application:
```bash
flutter run
```

### Backend Setup

1. Navigate to the backend directory:
```bash
cd backend
```

2. Install PHP dependencies:
```bash
composer install
```

3. Set up the database:
```bash
mysql -u root -p < database_setup.sql
```

4. Configure your database connection in the backend files

5. Start a local PHP server:
```bash
php -S localhost:8000
```

## Testing Credentials

For local development and testing, use the credentials provided in `backend/CREDENTIALS.md`. These are dummy accounts for testing purposes only.

## Development

### Building for Different Platforms

**Android:**
```bash
flutter build apk
```

**iOS:**
```bash
flutter build ios
```

**Web:**
```bash
flutter build web
```

## Dependencies

Key Flutter packages:
- `google_fonts` - Custom fonts
- `fl_chart` - Charts and graphs
- `http` - HTTP requests
- `shared_preferences` - Local storage
- `table_calendar` - Calendar widget
- `flutter_typeahead` - Search suggestions
- `file_picker` - File selection
- `sqflite` - Local database
- `image_cropper` - Image editing

## Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or suggestions, please open an issue on GitHub.
