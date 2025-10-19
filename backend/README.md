# Flutter Student Portal Backend

This directory contains the PHP backend for the Flutter Student Portal application.

## Setup Instructions

### 1. XAMPP Installation
1. Download and install XAMPP from [https://www.apachefriends.org/](https://www.apachefriends.org/)
2. Start Apache and MySQL services from XAMPP Control Panel

### 2. Database Setup
1. Open phpMyAdmin: http://localhost/phpmyadmin
2. Create a new database called `flutter_api`
3. Import the `database_setup.sql` file or run the SQL commands manually
4. The database will be created with sample data for testing

### 3. API File Setup
1. Copy `api.php` to your XAMPP htdocs folder: `C:\xampp\htdocs\`
2. The API will be accessible at: `http://localhost/api.php`

### 4. Test the API
You can test the API endpoints using tools like Postman or curl:

#### Test Login (POST)
```
URL: http://localhost/api.php?endpoint=login
Method: POST
Body: {
  "email": "john.doe@example.com",
  "password": "password123"
}
```

#### Test Get Users (GET)
```
URL: http://localhost/api.php?endpoint=users
Method: GET
```

#### Test Create User (POST)
```
URL: http://localhost/api.php?endpoint=user
Method: POST
Body: {
  "name": "New Student",
  "email": "newstudent@example.com",
  "role": "Student"
}
```

## API Endpoints

### Authentication
- `POST /api.php?endpoint=login` - User login
- `POST /api.php?endpoint=register` - User registration

### Users
- `GET /api.php?endpoint=users` - Get all users
- `GET /api.php?endpoint=user&id={id}` - Get user by ID
- `POST /api.php?endpoint=user` - Create new user
- `PUT /api.php?endpoint=user&id={id}` - Update user
- `DELETE /api.php?endpoint=user&id={id}` - Delete user

### User Profiles
- `GET /api.php?endpoint=profile&user_id={id}` - Get user profile
- `POST /api.php?endpoint=profile` - Create user profile
- `PUT /api.php?endpoint=profile&user_id={id}` - Update user profile

### Courses
- `GET /api.php?endpoint=courses` - Get all courses
- `POST /api.php?endpoint=course` - Create new course

### Attendance
- `GET /api.php?endpoint=attendance&user_id={id}` - Get user attendance
- `POST /api.php?endpoint=attendance` - Record attendance

## Database Schema

### Users Table
- `id` - Primary key
- `name` - User's full name
- `email` - Unique email address
- `password` - Hashed password
- `role` - User role (Student/Teacher/Admin)
- `created_at` - Account creation timestamp

### User Profiles Table
- `user_id` - Foreign key to users table
- `full_name`, `cnic`, `date_of_birth`, `gender`, `blood_group`
- `nationality`, `religion`, `roll_number`, `class`, `batch`
- `enrollment_date`, `phone`, `whatsapp`, `alternative_phone`
- `emergency_contact`, `emergency_relationship`
- `current_address`, `permanent_address`, `city`, `province`, `postal_code`

### Courses Table
- `id` - Primary key
- `name` - Course name
- `description` - Course description

### Attendance Table
- `id` - Primary key
- `user_id` - Foreign key to users table
- `course_id` - Foreign key to courses table
- `date` - Attendance date
- `status` - Present/Absent/Late/Leave
- `topic` - Class topic covered

## Sample Data

The database comes with sample data:
- **Users**: john.doe@example.com, jane.smith@example.com, admin@example.com
- **Password**: password123 (for all users)
- **Sample courses**: Mathematics, Physics, Computer Science, English Literature, History
- **Sample profile data** for John Doe
- **Sample attendance records**

## Troubleshooting

### Common Issues

1. **Database Connection Error**
   - Ensure MySQL service is running in XAMPP
   - Check database credentials in `api.php`
   - Verify database `flutter_api` exists

2. **CORS Issues**
   - The API includes CORS headers for Flutter app
   - If testing from browser, ensure CORS is properly configured

3. **File Not Found**
   - Ensure `api.php` is in the correct htdocs directory
   - Check file permissions

4. **Permission Denied**
   - Ensure XAMPP has proper permissions to read/write files

### Testing from Flutter

When testing from Flutter app:
- Use `http://10.0.2.2/api.php` for Android Emulator
- Use `http://localhost/api.php` for web
- Use your computer's IP address for physical device testing

## Security Notes

- This is a development setup - not recommended for production
- Passwords are hashed using PHP's `password_hash()` function
- Consider adding JWT tokens for production use
- Implement rate limiting for production environments
- Add input validation and sanitization for production use
