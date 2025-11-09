<?php
/**
 * Flutter Student Portal REST API
 * Handles user authentication, profile management, and data operations
 * 
 * Database: flutter_api
 * Tables: users, user_profiles, courses, attendance
 */

// Enable CORS for Flutter app
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json; charset=UTF-8");

// Prevent PHP notices/warnings from corrupting JSON output
// Show errors in server logs but not in response body
if (function_exists('ini_set')) {
    @ini_set('display_errors', '0');
    @ini_set('display_startup_errors', '0');
}

function upsertAssessmentCompletion($pdo, $input, $requester) {
    $kind = isset($input['kind']) ? strtolower(trim((string)$input['kind'])) : '';
    $classId = isset($input['class_id']) ? intval($input['class_id']) : 0;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : 0;
    $planItemId = isset($input['plan_item_id']) ? intval($input['plan_item_id']) : 0;
    $number = isset($input['number']) ? intval($input['number']) : null;
    $status = isset($input['status']) ? trim((string)$input['status']) : 'covered';
    $completedAtRaw = isset($input['completed_at']) ? trim((string)$input['completed_at']) : null;

    if (!in_array($kind, ['assignment', 'quiz'], true) || $classId <= 0 || $subjectId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid payload']);
        return;
    }

    if (!canManagePlanner($pdo, $requester, $classId, $subjectId)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    $completedAt = $completedAtRaw && $completedAtRaw !== '' ? normalizePlannerDateTime($completedAtRaw) : date('Y-m-d H:i:s');
    $status = in_array($status, ['scheduled','ready_for_verification','covered','deferred'], true) ? $status : 'covered';

    try {
        ensureAssessmentSchema($pdo);
        $pdo->beginTransaction();

        if ($kind === 'assignment') {
            if ($planItemId > 0) {
                $stmt = $pdo->prepare("UPDATE class_assignments SET status = ?, completed_at = ? WHERE plan_item_id = ? AND class_id = ? AND subject_id = ?");
                $stmt->execute([$status, $completedAt, $planItemId, $classId, $subjectId]);
            }
            if ($number !== null) {
                $stmt = $pdo->prepare("UPDATE class_assignments SET status = ?, completed_at = ? WHERE assignment_number = ? AND class_id = ? AND subject_id = ?");
                $stmt->execute([$status, $completedAt, $number, $classId, $subjectId]);
                $stmt = $pdo->prepare("UPDATE student_assignments SET coverage_status = ?, graded_at = CASE WHEN ? = 'covered' THEN COALESCE(graded_at, ?) ELSE graded_at END WHERE class_id = ? AND subject_id = ? AND assignment_number = ?");
                $stmt->execute([$status, $status, $completedAt, $classId, $subjectId, $number]);
            }
        } else {
            if ($planItemId > 0) {
                $stmt = $pdo->prepare("UPDATE class_quizzes SET status = ?, completed_at = ? WHERE plan_item_id = ? AND class_id = ? AND subject_id = ?");
                $stmt->execute([$status, $completedAt, $planItemId, $classId, $subjectId]);
            }
            if ($number !== null) {
                $stmt = $pdo->prepare("UPDATE class_quizzes SET status = ?, completed_at = ? WHERE quiz_number = ? AND class_id = ? AND subject_id = ?");
                $stmt->execute([$status, $completedAt, $number, $classId, $subjectId]);
                $stmt = $pdo->prepare("UPDATE student_quizzes SET coverage_status = ?, graded_at = CASE WHEN ? = 'covered' THEN COALESCE(graded_at, ?) ELSE graded_at END WHERE class_id = ? AND subject_id = ? AND quiz_number = ?");
                $stmt->execute([$status, $status, $completedAt, $classId, $subjectId, $number]);
            }
        }

        $pdo->commit();
        echo json_encode(['success' => true, 'status' => $status, 'completed_at' => $completedAt]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update assessment completion: ' . $e->getMessage()]);
    }
}

function fetchTermMarks($pdo, $table, $studentId, $classId = null) {
    $allowedTables = ['student_first_term_marks', 'student_final_term_marks'];
    if (!in_array($table, $allowedTables, true)) {
        throw new InvalidArgumentException('Invalid term marks table');
    }

    $sql = "SELECT tm.id,
                   tm.class_id,
                   c.name AS class_name,
                   tm.subject_id,
                   s.name AS subject_name,
                   tm.total_marks,
                   tm.obtained_marks,
                   tm.exam_date,
                   tm.remarks,
                   tm.created_at,
                   tm.updated_at
            FROM {$table} tm
            JOIN classes c ON c.id = tm.class_id
            JOIN subjects s ON s.id = tm.subject_id
            WHERE tm.student_user_id = ?";
    $params = [$studentId];
    if ($classId) {
        $sql .= " AND tm.class_id = ?";
        $params[] = $classId;
    }
    $sql .= " ORDER BY tm.exam_date IS NULL, tm.exam_date DESC, tm.updated_at DESC";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($rows as &$row) {
        $total = floatval($row['total_marks']);
        $obt = isset($row['obtained_marks']) ? floatval($row['obtained_marks']) : null;
        $row['percentage'] = ($obt === null || $total <= 0) ? null : round(($obt / $total) * 100, 2);
    }
    unset($row);

    return $rows;
}

function getStudentTermMarks($pdo, $requester, $termType) {
    $termType = strtolower(trim((string)$termType));
    $table = termTableFor($termType);
    if (!$table) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid term type']);
        return;
    }

    $studentId = isset($_GET['student_user_id']) ? intval($_GET['student_user_id']) : 0;
    if ($studentId <= 0) {
        $studentId = intval($requester['id']);
    }

    $classId = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
    if ($classId <= 0) {
        $classId = null;
    }

    $isAdmin = strtolower($requester['role'] ?? '') === 'admin';
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    if (!$isAdmin && !$isSuperAdmin && $studentId !== intval($requester['id'])) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    try {
        $rows = fetchTermMarks($pdo, $table, $studentId, $classId);
        echo json_encode(['success' => true, 'term' => $termType, 'marks' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch term marks: ' . $e->getMessage()]);
    }
}

function termTableFor($termType) {
    $termType = strtolower(trim((string)$termType));
    if ($termType === 'first' || $termType === 'first_term' || $termType === 'mid' || $termType === 'mid_term') {
        return 'student_first_term_marks';
    }
    if ($termType === 'final' || $termType === 'final_term') {
        return 'student_final_term_marks';
    }
    return null;
}

function upsertStudentTermMarks($pdo, $input, $requester, $termType) {
    $table = termTableFor($termType);
    if (!$table) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid term type']);
        return;
    }

    if (!(($requester['role'] ?? '') === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 0)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    $classId   = isset($input['class_id']) ? intval($input['class_id']) : null;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : null;
    if (!$classId || !$subjectId) {
        list($classId, $subjectId) = resolveClassAndSubject($pdo, $input, false);
    }
    $totalMarks = isset($input['total_marks']) ? intval($input['total_marks']) : 0;
    $entries = isset($input['entries']) && is_array($input['entries']) ? $input['entries'] : [];
    if (!$classId || !$subjectId || $totalMarks <= 0 || empty($entries)) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing/invalid payload']);
        return;
    }

    $examDate = isset($input['exam_date']) ? trim((string)$input['exam_date']) : null;
    if ($examDate === '') { $examDate = null; }
    $remarks = isset($input['remarks']) ? trim((string)$input['remarks']) : null;
    if ($remarks === '') { $remarks = null; }

    try {
        $pdo->beginTransaction();
        $stmt = $pdo->prepare(
            "INSERT INTO {$table} (class_id, subject_id, student_user_id, total_marks, obtained_marks, exam_date, remarks)
             VALUES (?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE total_marks = VALUES(total_marks), obtained_marks = VALUES(obtained_marks), exam_date = VALUES(exam_date), remarks = VALUES(remarks), updated_at = NOW()"
        );
        $affected = 0;
        foreach ($entries as $entry) {
            $studentId = isset($entry['student_user_id']) ? intval($entry['student_user_id']) : 0;
            if ($studentId <= 0) { continue; }
            $obt = isset($entry['obtained_marks']) ? floatval($entry['obtained_marks']) : null;
            if ($obt === null || $obt < 0) { continue; }
            $rowRemarks = isset($entry['remarks']) ? trim((string)$entry['remarks']) : $remarks;
            if ($rowRemarks === '') { $rowRemarks = null; }
            $rowExamDate = isset($entry['exam_date']) ? trim((string)$entry['exam_date']) : $examDate;
            if ($rowExamDate === '') { $rowExamDate = null; }
            $stmt->execute([$classId, $subjectId, $studentId, $totalMarks, $obt, $rowExamDate, $rowRemarks]);
            $affected += $stmt->rowCount();
        }
        $pdo->commit();
        echo json_encode(['success' => true, 'updated' => $affected]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to upsert term marks: ' . $e->getMessage()]);
    }
}

/**
 * Upload a profile picture for a user (stores in user_files table)
 * Admins may upload on behalf of any user. Non-admins can only upload their own picture.
 */
function handleUploadProfilePicture($pdo, $requester) {
    global $JWT_SECRET;

    if (!is_dir(USER_FILES_UPLOAD_DIR)) {
        @mkdir(USER_FILES_UPLOAD_DIR, 0775, true);
    }

    $targetUserId = isset($_POST['user_id']) ? intval($_POST['user_id']) : intval($requester['id'] ?? 0);
    if ($targetUserId <= 0) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'user_id is required']);
        return;
    }

    $isAdmin = ($requester['role'] ?? '') === 'Admin';
    if (!$isAdmin && (int)$targetUserId !== (int)($requester['id'] ?? 0)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'error' => 'Forbidden']);
        return;
    }

    if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'No file uploaded']);
        return;
    }

    $f = $_FILES['file'];
    $err = $f['error'] ?? UPLOAD_ERR_NO_FILE;
    if ($err !== UPLOAD_ERR_OK) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Upload error', 'code' => $err]);
        return;
    }

    $orig = basename($f['name']);
    $size = (int)$f['size'];
    $tmp  = $f['tmp_name'];
    $ext  = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
    $allowed = ['png','jpg','jpeg','gif','webp'];
    if ($ext && !in_array($ext, $allowed)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Unsupported file type']);
        return;
    }

    // Ensure target user exists (also retrieve name for logging/table)
    $userStmt = $pdo->prepare('SELECT name FROM users WHERE id = ? LIMIT 1');
    $userStmt->execute([$targetUserId]);
    $userRow = $userStmt->fetch(PDO::FETCH_ASSOC);
    if (!$userRow) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'User not found']);
        return;
    }

    $safeBase = 'profile_' . $targetUserId . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3));
    $stored   = $safeBase . ($ext ? ('.' . $ext) : '');
    $destPath = rtrim(USER_FILES_UPLOAD_DIR, '/\\') . '/' . $stored;
    if (!@move_uploaded_file($tmp, $destPath)) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Failed to store file']);
        return;
    }

    $mime = function_exists('mime_content_type') ? @mime_content_type($destPath) : null;
    if (!$mime || $mime === 'application/octet-stream') {
        switch ($ext) {
            case 'png':
                $mime = 'image/png';
                break;
            case 'jpg':
            case 'jpeg':
                $mime = 'image/jpeg';
                break;
            case 'gif':
                $mime = 'image/gif';
                break;
            case 'webp':
                $mime = 'image/webp';
                break;
            default:
                $mime = 'application/octet-stream';
        }
    }

    try {
        $stmt = $pdo->prepare("INSERT INTO user_files (user_id, user_name, original_file_name, stored_file_name, file_type, file_size, uploaded_at) VALUES (?, ?, ?, ?, ?, ?, NOW())");
        $stmt->execute([
            $targetUserId,
            (string)($userRow['name'] ?? ''),
            $orig,
            $stored,
            $mime,
            $size
        ]);

        $baseUrl = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
        $profilePictureUrl = $baseUrl . '/backend/api.php?endpoint=serve_file&file=' . urlencode($stored);

        echo json_encode([
            'success' => true,
            'stored_file' => $stored,
            'profile_picture_url' => $profilePictureUrl,
        ]);
    } catch (PDOException $e) {
        if (file_exists($destPath)) { @unlink($destPath); }
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'DB error: ' . $e->getMessage()]);
    }
}

/**
 * Superadmin: Create a challan for a student with optional file upload
 * Expects multipart/form-data:
 *   - student_user_id (int, required)
 *   - title (string, required)
 *   - category ('fee'|'fine'|'other', default 'fee')
 *   - amount (decimal, optional)
 *   - due_date (YYYY-MM-DD, optional)
 *   - file (PDF/JPG/PNG, optional) -> stored under ./uploads/challans
 */
function handleCreateChallan($pdo, $requester) {
    error_log('[DEBUG PHP] createChallan called');
    error_log('[DEBUG PHP] Requester: ' . json_encode($requester));
    
    // Auth: only Super Admin may create challans
    $isSA = (($requester['role'] ?? '') === 'Admin') && intval($requester['is_super_admin'] ?? 0) === 1;
    error_log('[DEBUG PHP] Is Super Admin: ' . ($isSA ? 'true' : 'false'));
    
    if (!$isSA) {
        error_log('[DEBUG PHP] Access denied - not super admin');
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    // Accept both JSON and form-data; prefer $_POST for file uploads
    error_log('[DEBUG PHP] $_POST data: ' . json_encode($_POST));
    error_log('[DEBUG PHP] $_FILES data: ' . json_encode($_FILES));
    
    $studentId = isset($_POST['student_user_id']) ? intval($_POST['student_user_id']) : 0;
    $title     = isset($_POST['title']) ? trim((string)$_POST['title']) : '';
    $category  = isset($_POST['category']) ? strtolower(trim((string)$_POST['category'])) : 'fee';
    $amountRaw = isset($_POST['amount']) ? (string)$_POST['amount'] : null;
    $dueDate   = isset($_POST['due_date']) ? (string)$_POST['due_date'] : null; // YYYY-MM-DD

    error_log('[DEBUG PHP] Parsed values:');
    error_log('[DEBUG PHP] - studentId: ' . $studentId);
    error_log('[DEBUG PHP] - title: ' . $title);
    error_log('[DEBUG PHP] - category: ' . $category);
    error_log('[DEBUG PHP] - amountRaw: ' . $amountRaw);
    error_log('[DEBUG PHP] - dueDate: ' . $dueDate);

    if ($studentId <= 0 || $title === '' || !in_array($category, ['fee','fine','other'])) {
        error_log('[DEBUG PHP] Validation failed - studentId: ' . $studentId . ', title: "' . $title . '", category: ' . $category);
        http_response_code(400);
        echo json_encode(['error' => 'student_user_id, title, and valid category are required']);
        return;
    }

    // Validate student exists
    $st = $pdo->prepare("SELECT u.id FROM users u JOIN students s ON s.user_id = u.id WHERE u.id = ? LIMIT 1");
    $st->execute([$studentId]);
    $exists = $st->fetch(PDO::FETCH_ASSOC);
    if (!$exists) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid student_user_id']);
        return;
    }

    // Ensure upload dir exists
    $baseDir = defined('CHALLANS_UPLOAD_DIR') ? CHALLANS_UPLOAD_DIR : (rtrim(__DIR__, '/\\') . '/uploads/challans');
    if (!is_dir($baseDir)) {
        @mkdir($baseDir, 0777, true);
    }

    $fileInfo = [
        'stored'    => null,
        'original'  => null,
        'mime'      => null,
        'size'      => null,
    ];

    // Handle file upload if provided
    if (isset($_FILES['file']) && is_array($_FILES['file']) && ($_FILES['file']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
        $err = $_FILES['file']['error'];
        if ($err !== UPLOAD_ERR_OK) {
            http_response_code(400);
            echo json_encode(['error' => 'File upload error', 'code' => $err]);
            return;
        }
        $tmpPath = $_FILES['file']['tmp_name'];
        $orig    = $_FILES['file']['name'];
        $size    = (int)$_FILES['file']['size'];
        $ext     = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
        $allowed = ['pdf','jpg','jpeg','png','doc','docx'];
        if (!in_array($ext, $allowed)) {
            http_response_code(400);
            echo json_encode(['error' => 'Unsupported file type']);
            return;
        }
        $safeBase = 'challan_' . $studentId . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3));
        $stored   = $safeBase . ($ext ? ('.' . $ext) : '');
        $destPath = rtrim($baseDir, '/\\') . '/' . $stored;
        if (!@move_uploaded_file($tmpPath, $destPath)) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to store uploaded file']);
            return;
        }
        // Detect mime type best-effort
        $mime = function_exists('mime_content_type') ? @mime_content_type($destPath) : null;
        $fileInfo = [
            'stored'   => $stored,
            'original' => $orig,
            'mime'     => $mime,
            'size'     => $size,
        ];
    }

    try {
        $sql = "INSERT INTO challan (
                    student_user_id, title, category, amount, due_date, status,
                    challan_file_name, challan_original_file_name, challan_mime_type, challan_file_size,
                    created_by, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 'unpaid', ?, ?, ?, ?, ?, NOW(), NOW())";
        $stmt = $pdo->prepare($sql);
        $amount = $amountRaw !== null && $amountRaw !== '' ? floatval($amountRaw) : null;
        $stmt->execute([
            $studentId,
            $title,
            $category,
            $amount,
            $dueDate,
            $fileInfo['stored'],
            $fileInfo['original'],
            $fileInfo['mime'],
            $fileInfo['size'],
            intval($requester['id'])
        ]);
        echo json_encode(['success' => true, 'challan_id' => $pdo->lastInsertId()]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create challan: ' . $e->getMessage()]);
    }
}

/**
 * List challans - Admin sees all, Student sees own
 */
function listChallans($pdo, $requester) {
    error_log('[DEBUG PHP] listChallans called for user: ' . $requester['id']);
    
    $isAdmin = ($requester['role'] ?? '') === 'Admin';
    $studentId = isset($_GET['student_id']) ? intval($_GET['student_id']) : null;
    
    if ($isAdmin) {
        // Admin can see all challans or filter by student
        $sql = "SELECT c.*, u.name as student_name, u.email as student_email 
                FROM challan c 
                JOIN users u ON c.student_user_id = u.id 
                WHERE 1=1";
        $params = [];
        
        if ($studentId) {
            $sql .= " AND c.student_user_id = ?";
            $params[] = $studentId;
        }
        
        $sql .= " ORDER BY c.created_at DESC";
        
    } else {
        // Student sees only their own challans
        $sql = "SELECT c.*, u.name as student_name, u.email as student_email 
                FROM challan c 
                JOIN users u ON c.student_user_id = u.id 
                WHERE c.student_user_id = ? 
                ORDER BY c.created_at DESC";
        $params = [$requester['id']];
    }
    
    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $challans = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode(['success' => true, 'challans' => $challans]);
    } catch (PDOException $e) {
        error_log('[DEBUG PHP] Error listing challans: ' . $e->getMessage());
        http_response_code(500);
        echo json_encode(['error' => 'Failed to list challans: ' . $e->getMessage()]);
    }
}

/**
 * Student: Upload payment proof for a challan (multipart/form-data)
 * Fields: challan_id, payment_proof
 */
function handleUploadPaymentProof($pdo, $requester) {
    error_log('[DEBUG PHP] handleUploadPaymentProof called for user: ' . ($requester['id'] ?? 'unknown'));
    // Only students can upload payment proof
    if (($requester['role'] ?? '') !== 'Student') {
        http_response_code(403);
        echo json_encode(['success' => false, 'error' => 'Access denied']);
        return;
    }

    $challanId = isset($_POST['challan_id']) ? intval($_POST['challan_id']) : 0;
    if ($challanId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'challan_id is required']);
        return;
    }

    // Verify challan belongs to this student
    $stmt = $pdo->prepare("SELECT id FROM challan WHERE id = ? AND student_user_id = ? LIMIT 1");
    $stmt->execute([$challanId, $requester['id']]);
    if (!$stmt->fetch()) {
        http_response_code(404);
        echo json_encode(['error' => 'Challan not found or access denied']);
        return;
    }

    // Ensure upload dir exists
    $baseDir = defined('CHALLANS_UPLOAD_DIR') ? CHALLANS_UPLOAD_DIR : (rtrim(__DIR__, '/\\') . '/uploads/challans');
    if (!is_dir($baseDir)) {
        @mkdir($baseDir, 0777, true);
    }

    // Handle file upload
    if (!isset($_FILES['payment_proof']) || $_FILES['payment_proof']['error'] !== UPLOAD_ERR_OK) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Payment proof file is required']);
        return;
    }

    $tmpPath = $_FILES['payment_proof']['tmp_name'];
    $orig = $_FILES['payment_proof']['name'];
    $size = (int)$_FILES['payment_proof']['size'];
    $ext = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
    $allowed = ['pdf','jpg','jpeg','png','doc','docx'];

    if (!in_array($ext, $allowed)) {
        http_response_code(400);
        echo json_encode(['error' => 'Unsupported file type']);
        return;
    }

    // Create proofs subdirectory
    $proofsDir = rtrim($baseDir, '/\\') . '/proofs';
    if (!is_dir($proofsDir)) {
        @mkdir($proofsDir, 0777, true);
    }

    $safeBase = 'proof_' . $challanId . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3));
    $stored = $safeBase . ($ext ? ('.' . $ext) : '');
    $destPath = $proofsDir . '/' . $stored;

    if (!@move_uploaded_file($tmpPath, $destPath)) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to store proof file']);
        return;
    }

    $mime = function_exists('mime_content_type') ? @mime_content_type($destPath) : null;

    try {
        $sql = "UPDATE challan SET 
                    proof_file_name = ?, 
                    proof_original_file_name = ?, 
                    proof_mime_type = ?, 
                    proof_file_size = ?,
                    status = 'processing',
                    updated_at = NOW()
                WHERE id = ?";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$stored, $orig, $mime, $size, $challanId]);

        echo json_encode(['success' => true, 'message' => 'Proof uploaded successfully']);
    } catch (PDOException $e) {
        error_log('[DEBUG PHP] Error updating challan with proof: ' . $e->getMessage());
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update challan: ' . $e->getMessage()]);
    }
}

/**
 * Admin: Verify or reject challan payment
 */
function verifyChallan($pdo, $requester) {
    error_log('[DEBUG PHP] verifyChallan called');
    
    // Only admins can verify
    if (($requester['role'] ?? '') !== 'Admin') {
        http_response_code(403);
        echo json_encode(['error' => 'Only admins can verify challans']);
        return;
    }
    
    $input = json_decode(file_get_contents('php://input'), true);
    $challanId = isset($input['challan_id']) ? intval($input['challan_id']) : 0;
    $action = isset($input['action']) ? trim($input['action']) : '';
    $remarks = isset($input['remarks']) ? trim($input['remarks']) : null;
    
    if ($challanId <= 0 || !in_array($action, ['verify', 'reject'])) {
        http_response_code(400);
        echo json_encode(['error' => 'challan_id and valid action (verify/reject) are required']);
        return;
    }
    
    $newStatus = ($action === 'verify') ? 'verified' : 'rejected';
    
    try {
        // Some databases may not have admin_remarks column; update only standard fields
        $sql = "UPDATE challan SET 
                    status = ?, 
                    reviewed_by = ?, 
                    reviewed_at = NOW(),
                    updated_at = NOW()
                WHERE id = ?";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$newStatus, $requester['id'], $challanId]);
        
        if ($stmt->rowCount() === 0) {
            http_response_code(404);
            echo json_encode(['error' => 'Challan not found']);
            return;
        }
        
        echo json_encode(['success' => true, 'message' => 'Challan ' . $action . 'd successfully']);
    } catch (PDOException $e) {
        error_log('[DEBUG PHP] Error verifying challan: ' . $e->getMessage());
        http_response_code(500);
        echo json_encode(['error' => 'Failed to verify challan: ' . $e->getMessage()]);
    }
}

// Upload directory for assignment files relative to this api.php location
// Using __DIR__ keeps it OS-agnostic and aligned with repo structure
if (!defined('ASSIGNMENTS_UPLOAD_DIR')) {
    define('ASSIGNMENTS_UPLOAD_DIR', rtrim(__DIR__, '/\\') . '/uploads/assignments');
}

// Upload directory for challan files relative to this api.php location
if (!defined('CHALLANS_UPLOAD_DIR')) {
    define('CHALLANS_UPLOAD_DIR', rtrim(__DIR__, '/\\') . '/uploads/challans');
}

// Upload directory for generic user files relative to this api.php location
if (!defined('USER_FILES_UPLOAD_DIR')) {
    define('USER_FILES_UPLOAD_DIR', rtrim(__DIR__, '/\\') . '/uploads/user_files');
}

// Clean output buffer to prevent any whitespace/characters before JSON
if (ob_get_level()) {
    ob_clean();
}

/**
 * Tickets: create (Student), list (Student own or Superadmin all), reply (Superadmin with fixed replies)
 */
function createTicket($pdo, $input, $requester) {
    // Only Students can create tickets (optionally allow SA)
    $role = strtolower($requester['role'] ?? '');
    $isSA = intval($requester['is_super_admin'] ?? 0) === 1;
    if (!($role === 'student' || $isSA)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    $level1 = isset($input['level1']) ? strtolower(trim((string)$input['level1'])) : '';
    $level2 = isset($input['level2']) ? strtolower(trim((string)$input['level2'])) : '';
    $content = isset($input['content']) ? trim((string)$input['content']) : '';
    $validL1 = ['request','query','complaint'];
    $validL2 = [
        'request' => ['fee concession','fines waiver'],
        'query' => ['subject related','portal not working'],
        'complaint' => ['teacher','student'],
    ];
    if (!in_array($level1, $validL1) || $content === '' || !in_array($level2, $validL2[$level1] ?? [])) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid payload']);
        return;
    }
    try {
        $stmt = $pdo->prepare("INSERT INTO tickets (created_by, level1, level2, content, status, created_at, updated_at) VALUES (?, ?, ?, ?, 'open', NOW(), NOW())");
        $stmt->execute([intval($requester['id']), $level1, $level2, $content]);
        echo json_encode(['success' => true, 'ticket_id' => $pdo->lastInsertId()]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create ticket: ' . $e->getMessage()]);
    }
}

function listTickets($pdo, $requester) {
    $role = strtolower($requester['role'] ?? '');
    $isSA = intval($requester['is_super_admin'] ?? 0) === 1;
    $status = isset($_GET['status']) ? strtolower(trim((string)$_GET['status'])) : null;
    $allowedStatus = ['open','in_progress','resolved','closed'];
    $where = '';
    $params = [];
    if ($isSA) {
        $where = '';
    } else if ($role === 'student') {
        $where = 'WHERE t.created_by = ?';
        $params[] = intval($requester['id']);
    } else {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    if ($status && in_array($status, $allowedStatus)) {
        $where .= ($where ? ' AND ' : 'WHERE ') . 't.status = ?';
        $params[] = $status;
    }
    try {
        $sql = "SELECT t.id, t.level1, t.level2, t.content, t.status, t.created_at, t.updated_at,
                       u.name AS creator_name, u.email AS creator_email
                FROM tickets t
                JOIN users u ON u.id = t.created_by
                $where
                ORDER BY t.created_at DESC
                LIMIT 100";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'tickets' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch tickets: ' . $e->getMessage()]);
    }
}

function replyTicket($pdo, $input, $requester) {
    // Only Super Admin may reply with fixed templates
    $isSA = (($requester['role'] ?? '') === 'Admin') && intval($requester['is_super_admin'] ?? 0) === 1;
    if (!$isSA) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    $ticketId = isset($input['ticket_id']) ? intval($input['ticket_id']) : 0;
    $replyKey = isset($input['reply_key']) ? strtolower(trim((string)$input['reply_key'])) : '';
    $status = isset($input['status']) ? strtolower(trim((string)$input['status'])) : null;
    $fixed = [
        'acknowledged' => 'We have received your ticket and will get back to you shortly.',
        'in_review' => 'Your ticket is under review.',
        'resolved' => 'Your issue has been resolved. Please confirm.',
        'closed' => 'The ticket has been closed. Thank you.',
    ];
    $allowedStatus = ['open','in_progress','resolved','closed'];
    if ($ticketId <= 0 || !array_key_exists($replyKey, $fixed)) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid payload']);
        return;
    }
    try {
        $pdo->beginTransaction();
        $ins = $pdo->prepare("INSERT INTO ticket_replies (ticket_id, replied_by, reply_text, created_at) VALUES (?, ?, ?, NOW())");
        $ins->execute([$ticketId, intval($requester['id']), $fixed[$replyKey]]);
        if ($status && in_array($status, $allowedStatus)) {
            $up = $pdo->prepare("UPDATE tickets SET status = ?, updated_at = NOW() WHERE id = ?");
            $up->execute([$status, $ticketId]);
        }
        $pdo->commit();
        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        http_response_code(500);
        echo json_encode(['error' => 'Failed to reply: ' . $e->getMessage()]);
    }
}
@error_reporting(E_ERROR | E_PARSE);

// Ensure a clean output buffer so only JSON is sent
if (function_exists('ob_get_level') && ob_get_level() === 0) {
    @ob_start();
}


// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

/**
 * Enrollment Helpers & Endpoints
 */
function autoEnrollStudent($pdo, $studentUserId) {
    // Fetch student's class and stream (batch) from profile
    $stmt = $pdo->prepare("SELECT p.class AS class_name, p.batch AS stream FROM user_profiles p WHERE p.user_id = ? LIMIT 1");
    $stmt->execute([$studentUserId]);
    $prof = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$prof || !$prof['class_name']) {
        throw new Exception('Student profile with class is required');
    }

    $className = trim($prof['class_name']);
    $streamRaw = isset($prof['stream']) ? strtolower(trim($prof['stream'])) : '';

    // Resolve class_id and level
    $stmt = $pdo->prepare("SELECT id, level FROM classes WHERE name = ? LIMIT 1");
    $stmt->execute([$className]);
    $cls = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$cls) { throw new Exception('Class not found: ' . $className); }
    $classId = (int)$cls['id'];
    $level = $cls['level'];

    // Determine stream logic for Secondary
    $isSecondary = ($level === 'Secondary');
    $wantBio = $isSecondary && (strpos($streamRaw, 'bio') !== false);
    $wantComp = $isSecondary && (strpos($streamRaw, 'comp') !== false);

    // Gather subject assignments for this class
    $sql = "SELECT a.subject_id, s.name AS subject_name
            FROM teacher_class_subject_assignments a
            JOIN subjects s ON s.id = a.subject_id
            WHERE a.class_id = ?
            ORDER BY s.name";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$classId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($rows)) {
        // No explicit assignments: enroll none (conservative). Return 0.
        return 0;
    }

    // Apply stream filtering for Secondary
    $subjectIds = [];
    foreach ($rows as $r) {
        $sid = (int)$r['subject_id'];
        $sname = strtolower($r['subject_name']);
        if ($isSecondary) {
            if ($wantBio && $sname === 'computer') { continue; }
            if ($wantComp && $sname === 'biology') { continue; }
        }
        $subjectIds[] = $sid;
    }

    if (empty($subjectIds)) { return 0; }

    // Upsert enrollments: remove old for this class, insert current set
    $pdo->beginTransaction();
    try {
        $del = $pdo->prepare("DELETE FROM student_enrollments WHERE student_user_id = ? AND class_id = ?");
        $del->execute([$studentUserId, $classId]);

        $ins = $pdo->prepare("INSERT INTO student_enrollments (student_user_id, class_id, subject_id, created_at) VALUES (?, ?, ?, NOW())");
        $count = 0;
        foreach ($subjectIds as $sid) {
            $ins->execute([$studentUserId, $classId, $sid]);
            $count += $ins->rowCount();
        }
        $pdo->commit();
        return $count;
    } catch (Exception $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        throw $e;
    }
}

function getMyStudentCourses($pdo, $requester) {
    // Only for Students; Admin/Teacher may pass user_id query to inspect
    $userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : (int)$requester['id'];
    if (($requester['role'] ?? '') !== 'Admin' && $userId !== (int)$requester['id']) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    // Determine current class from profile
    $stmt = $pdo->prepare("SELECT p.class AS class_name FROM user_profiles p WHERE p.user_id = ? LIMIT 1");
    $stmt->execute([$userId]);
    $prof = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$prof || !$prof['class_name']) {
        echo json_encode(['success' => true, 'courses' => []]);
        return;
    }
    $className = $prof['class_name'];

    $stmt = $pdo->prepare("SELECT id FROM classes WHERE name = ? LIMIT 1");
    $stmt->execute([$className]);
    $cls = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$cls) { echo json_encode(['success' => true, 'courses' => []]); return; }
    $classId = (int)$cls['id'];

    // Join enrollments with subjects and teacher assignment (optional) for richer data
    $sql = "SELECT se.subject_id, s.name AS subject_name,
                   a.teacher_user_id,
                   u.name AS teacher_name
            FROM student_enrollments se
            JOIN subjects s ON s.id = se.subject_id
            LEFT JOIN teacher_class_subject_assignments a ON a.class_id = se.class_id AND a.subject_id = se.subject_id
            LEFT JOIN users u ON u.id = a.teacher_user_id
            WHERE se.student_user_id = ? AND se.class_id = ?
            ORDER BY s.name";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$userId, $classId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'courses' => $rows]);
}

/**
 * Teacher: list previous class attendance dates with counts
 * GET params: class_name (required), limit (optional, default 30)
 */
function getClassAttendanceHistory($pdo, $requester) {
    if (!(($requester['role'] ?? '') === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 0)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    $className = isset($_GET['class_name']) ? trim((string)$_GET['class_name']) : '';
    $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 30;
    if ($className === '') {
        http_response_code(400);
        echo json_encode(['error' => 'class_name is required']);
        return;
    }
    $limit = max(1, min(200, $limit));
    try {
        $sql = "SELECT attendance_date, COUNT(*) AS entries, 
                       SUM(CASE WHEN status='present' THEN 1 ELSE 0 END) AS present_count,
                       SUM(CASE WHEN status='absent' THEN 1 ELSE 0 END) AS absent_count,
                       SUM(CASE WHEN status='leave' THEN 1 ELSE 0 END) AS leave_count
                FROM class_attendance
                WHERE class_name = ?
                GROUP BY attendance_date
                ORDER BY attendance_date DESC
                LIMIT $limit";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$className]);
        echo json_encode(['success' => true, 'history' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch attendance history: ' . $e->getMessage()]);
    }
}

/**
 * Teacher-only: list classes assigned to the authenticated teacher
 * Returns [{ class_id, class_name, level }]
 */
function getTeacherClasses($pdo, $requester) {
    $dbRole = strtolower($requester['role'] ?? '');
    $isSA   = intval($requester['is_super_admin'] ?? 0);
    $userId = intval($requester['id'] ?? 0);
    // Treat Admin (is_super_admin=0) as Teacher
    if (!($dbRole === 'admin' && $isSA === 0) || $userId <= 0) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    try {
        $sql = "SELECT DISTINCT c.id AS class_id, c.name AS class_name, c.level AS level
                FROM teacher_class_subject_assignments a
                JOIN classes c ON c.id = a.class_id
                WHERE a.teacher_user_id = ?
                ORDER BY c.level, c.name";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'classes' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch teacher classes: ' . $e->getMessage()]);
    }
}

/**
 * Teacher-only: list students for a class if the teacher is assigned to that class
 */
// GET param: class_name
function getClassStudentsForTeacher($pdo, $requester) {
    // Verify the requester is a teacher (Admin role but not super admin)
    if ($requester['role'] !== 'Admin' || $requester['is_super_admin']) {
        http_response_code(403);
        echo json_encode(['error' => 'Only teachers can view class students']);
        return;
    }

    // Get class_name from query parameters
    $className = isset($_GET['class_name']) ? trim($_GET['class_name']) : '';
    if (empty($className)) {
        http_response_code(400);
        echo json_encode(['error' => 'class_name parameter is required']);
        return;
    }

    try {
        // First, verify the teacher is assigned to this class
        $stmt = $pdo->prepare("
            SELECT tc.id 
            FROM teacher_classes tc
            JOIN classes c ON tc.class_id = c.id
            WHERE tc.teacher_id = ? AND c.name = ?
            LIMIT 1
        ");
        $stmt->execute([$requester['id'], $className]);
        $isAssigned = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$isAssigned) {
            http_response_code(403);
            echo json_encode(['error' => 'You are not assigned to this class']);
            return;
        }

        // Get all students in the class
        $stmt = $pdo->prepare("
            SELECT u.id, u.username, up.first_name, up.last_name, up.roll_number
            FROM users u
            JOIN user_profiles up ON u.id = up.user_id
            JOIN classes c ON up.class = c.name
            WHERE u.role = 'Student' AND c.name = ?
            ORDER BY up.roll_number, up.first_name, up.last_name
        ");
        $stmt->execute([$className]);
        $students = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Return the list of students
        header('Content-Type: application/json');
        echo json_encode(['data' => $students]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
    }
}

function normalizePlannerDateTime($value) {
    if (!isset($value)) {
        return null;
    }
    $value = trim((string)$value);
    if ($value === '') {
        return null;
    }
    $timestamp = strtotime($value);
    if ($timestamp === false) {
        return null;
    }
    return date('Y-m-d H:i:s', $timestamp);
}

function normalizePlannerDate($value) {
    if (!isset($value)) {
        return null;
    }
    $value = trim((string)$value);
    if ($value === '') {
        return null;
    }
    $timestamp = strtotime($value);
    if ($timestamp === false) {
        return null;
    }
    return date('Y-m-d', $timestamp);
}

function plannerLog($tag, $context = []) {
    $timestamp = date('c');
    if (!is_array($context)) {
        $context = ['message' => (string)$context];
    }
    $entry = [
        'time' => $timestamp,
        'tag' => $tag,
        'context' => $context,
    ];
    error_log('[planner] ' . json_encode($entry));
}

function canManagePlanner($pdo, $requester, $classId, $subjectId) {
    $role = strtolower($requester['role'] ?? '');
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    if ($isSuperAdmin) {
        plannerLog('canManagePlanner.super_admin', ['class_id' => $classId, 'subject_id' => $subjectId, 'user_id' => $requester['id'] ?? null]);
        return true;
    }
    if (!in_array($role, ['admin', 'teacher'], true)) {
        plannerLog('canManagePlanner.denied_role', ['class_id' => $classId, 'subject_id' => $subjectId, 'user_id' => $requester['id'] ?? null, 'role' => $role]);
        return false;
    }

    $teacherId = intval($requester['id'] ?? 0);
    if ($teacherId <= 0) {
        plannerLog('canManagePlanner.denied_no_user_id', ['class_id' => $classId, 'subject_id' => $subjectId]);
        return false;
    }

    $stmt = $pdo->prepare("SELECT 1 FROM teacher_class_subject_assignments WHERE class_id = ? AND subject_id = ? AND teacher_user_id = ? LIMIT 1");
    $stmt->execute([$classId, $subjectId, $teacherId]);
    if ($stmt->fetchColumn()) {
        plannerLog('canManagePlanner.allowed_assignment', ['class_id' => $classId, 'subject_id' => $subjectId, 'user_id' => $teacherId]);
        return true;
    }

    // Allow non-super admins with Admin role to manage even without explicit assignment (e.g., coordinators)
    if ($role === 'admin') {
        plannerLog('canManagePlanner.allowed_admin_override', ['class_id' => $classId, 'subject_id' => $subjectId, 'user_id' => $teacherId]);
        return true;
    }

    plannerLog('canManagePlanner.denied_no_assignment', ['class_id' => $classId, 'subject_id' => $subjectId, 'user_id' => $teacherId]);
    return false;
}

function fetchPlannerPlanRow($pdo, $planId) {
    $stmt = $pdo->prepare("SELECT * FROM class_subject_plans WHERE id = ? LIMIT 1");
    $stmt->execute([$planId]);
    return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

function fetchPlannerPlanByContext($pdo, $classId, $subjectId, $teacherAssignmentId = null) {
    $sql = "SELECT * FROM class_subject_plans WHERE class_id = ? AND subject_id = ?";
    $params = [$classId, $subjectId];
    if ($teacherAssignmentId) {
        $sql .= " AND teacher_assignment_id = ?";
        $params[] = $teacherAssignmentId;
    }
    $sql .= " ORDER BY status = 'active' DESC, updated_at DESC LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

function autoAdvancePlannerStatuses($pdo, $planId) {
    $stmt = $pdo->prepare(
        "UPDATE class_subject_plan_items
         SET status = 'ready_for_verification', status_changed_at = NOW()
         WHERE plan_id = ?
           AND status = 'scheduled'
           AND scheduled_for IS NOT NULL
           AND scheduled_for <= NOW()"
    );
    $stmt->execute([$planId]);
}

function loadPlannerSessions($pdo, $planItemId) {
    $stmt = $pdo->prepare("SELECT session_date, notes, status FROM class_subject_plan_sessions WHERE plan_item_id = ? ORDER BY session_date ASC");
    $stmt->execute([$planItemId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    return array_map(function ($row) {
        return [
            'session_date' => $row['session_date'],
            'notes' => $row['notes'],
            'status' => $row['status'],
        ];
    }, $rows);
}

function loadPlannerItems($pdo, $planId) {
    $stmt = $pdo->prepare(
        "SELECT * FROM class_subject_plan_items
         WHERE plan_id = ?
         ORDER BY (scheduled_for IS NULL) ASC, scheduled_for ASC, created_at ASC"
    );
    $stmt->execute([$planId]);
    $items = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($items as &$item) {
        $item['sessions'] = loadPlannerSessions($pdo, (int)$item['id']);
    }
    unset($item);
    return $items;
}

function fetchPlannerPlanItem($pdo, $itemId) {
    $stmt = $pdo->prepare(
        "SELECT i.*, p.class_id, p.subject_id
         FROM class_subject_plan_items i
         JOIN class_subject_plans p ON p.id = i.plan_id
         WHERE i.id = ?
         LIMIT 1"
    );
    $stmt->execute([$itemId]);
    return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
}

function resolveAssignmentTeacherUserId($pdo, $teacherAssignmentId) {
    if (!$teacherAssignmentId) {
        return null;
    }
    $stmt = $pdo->prepare("SELECT teacher_user_id FROM teacher_class_subject_assignments WHERE id = ? LIMIT 1");
    $stmt->execute([$teacherAssignmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ? intval($row['teacher_user_id']) : null;
}

function syncLinkedAssessmentCoverage($pdo, $planItemId, $status) {
    if (!$status) {
        return;
    }
    $stmt = $pdo->prepare("UPDATE student_assignments SET coverage_status = ? WHERE plan_item_id = ?");
    $stmt->execute([$status, $planItemId]);
    $stmt = $pdo->prepare("UPDATE student_quizzes SET coverage_status = ? WHERE plan_item_id = ?");
    $stmt->execute([$status, $planItemId]);
}

function ensureAssessmentSchema($pdo) {
    static $schemaEnsured = false;
    if ($schemaEnsured) {
        return;
    }
    $schemaEnsured = true;

    $ddlStatements = [
        "ALTER TABLE class_assignments ADD COLUMN plan_item_id INT NULL AFTER subject_id",
        "ALTER TABLE class_assignments ADD COLUMN status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled' AFTER deadline",
        "ALTER TABLE class_assignments ADD COLUMN completed_at DATETIME NULL AFTER status",
        "ALTER TABLE class_assignments ADD INDEX idx_ca_plan_item (plan_item_id)",
        "ALTER TABLE class_quizzes ADD COLUMN plan_item_id INT NULL AFTER subject_id",
        "ALTER TABLE class_quizzes ADD COLUMN status ENUM('scheduled','ready_for_verification','covered','deferred') NOT NULL DEFAULT 'scheduled' AFTER deadline",
        "ALTER TABLE class_quizzes ADD COLUMN completed_at DATETIME NULL AFTER status",
        "ALTER TABLE class_quizzes ADD INDEX idx_cq_plan_item (plan_item_id)",
    ];

    foreach ($ddlStatements as $sql) {
        try {
            $pdo->exec($sql);
        } catch (Exception $e) {
            // Ignore schema errors (e.g. insufficient privileges or unsupported IF NOT EXISTS)
        }
    }
}

function upsertClassAssignmentForPlanItem($pdo, $plan, $itemId, $title, $description, $deadline, $status) {
    ensureAssessmentSchema($pdo);

    $classId = intval($plan['class_id'] ?? 0);
    $subjectId = intval($plan['subject_id'] ?? 0);
    if ($classId <= 0 || $subjectId <= 0 || $itemId <= 0) {
        return [null, null];
    }

    $stmt = $pdo->prepare("SELECT id, assignment_number FROM class_assignments WHERE plan_item_id = ? LIMIT 1");
    $stmt->execute([$itemId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    $assignmentName = $title ?: ($description ?: 'Assignment');
    $deadlineValue = $deadline ?: null;

    if ($row) {
        $update = $pdo->prepare(
            "UPDATE class_assignments
             SET assignment_name = ?, description = ?, deadline = ?, status = ?, updated_at = NOW()
             WHERE id = ?"
        );
        $update->execute([
            $assignmentName,
            $description ?: null,
            $deadlineValue,
            $status,
            intval($row['id']),
        ]);
        return [intval($row['assignment_number']), intval($row['id'])];
    }

    $stmt = $pdo->prepare("SELECT COALESCE(MAX(assignment_number), 0) FROM class_assignments WHERE class_id = ? AND subject_id = ?");
    $stmt->execute([$classId, $subjectId]);
    $nextNumber = intval($stmt->fetchColumn()) + 1;

    $insert = $pdo->prepare(
        "INSERT INTO class_assignments
            (class_id, subject_id, plan_item_id, assignment_number, assignment_name, description, deadline, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())"
    );
    $insert->execute([
        $classId,
        $subjectId,
        $itemId,
        $nextNumber,
        $assignmentName,
        $description ?: null,
        $deadlineValue,
        $status,
    ]);

    return [$nextNumber, intval($pdo->lastInsertId())];
}

function upsertClassQuizForPlanItem($pdo, $plan, $itemId, $title, $topic, $scheduledAt, $status) {
    ensureAssessmentSchema($pdo);

    $classId = intval($plan['class_id'] ?? 0);
    $subjectId = intval($plan['subject_id'] ?? 0);
    if ($classId <= 0 || $subjectId <= 0 || $itemId <= 0) {
        return [null, null];
    }

    $stmt = $pdo->prepare("SELECT id, quiz_number FROM class_quizzes WHERE plan_item_id = ? LIMIT 1");
    $stmt->execute([$itemId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    $quizName = $title ?: ($topic ?: 'Quiz');
    $deadlineValue = $scheduledAt ?: null;

    if ($row) {
        $update = $pdo->prepare(
            "UPDATE class_quizzes
             SET quiz_name = ?, description = ?, deadline = ?, status = ?, updated_at = NOW()
             WHERE id = ?"
        );
        $update->execute([
            $quizName,
            $topic ?: null,
            $deadlineValue,
            $status,
            intval($row['id']),
        ]);
        return [intval($row['quiz_number']), intval($row['id'])];
    }

    $stmt = $pdo->prepare("SELECT COALESCE(MAX(quiz_number), 0) FROM class_quizzes WHERE class_id = ? AND subject_id = ?");
    $stmt->execute([$classId, $subjectId]);
    $nextNumber = intval($stmt->fetchColumn()) + 1;

    $insert = $pdo->prepare(
        "INSERT INTO class_quizzes
            (class_id, subject_id, plan_item_id, quiz_number, quiz_name, description, deadline, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())"
    );
    $insert->execute([
        $classId,
        $subjectId,
        $itemId,
        $nextNumber,
        $quizName,
        $topic ?: null,
        $deadlineValue,
        $status,
    ]);

    return [$nextNumber, intval($pdo->lastInsertId())];
}

function fetchAssessmentMarksSummary($pdo, $kind, $classId, $subjectId) {
    if ($kind === 'assignment') {
        $stmt = $pdo->prepare(
            "SELECT assignment_number AS number,
                    MAX(total_marks) AS total_marks,
                    COUNT(*) AS student_count,
                    SUM(CASE WHEN obtained_marks IS NOT NULL THEN 1 ELSE 0 END) AS graded_count,
                    MAX(updated_at) AS updated_at
             FROM student_assignments
             WHERE class_id = ? AND subject_id = ? AND assignment_number IS NOT NULL
             GROUP BY assignment_number"
        );
    } else {
        $stmt = $pdo->prepare(
            "SELECT quiz_number AS number,
                    MAX(total_marks) AS total_marks,
                    COUNT(*) AS student_count,
                    SUM(CASE WHEN obtained_marks IS NOT NULL THEN 1 ELSE 0 END) AS graded_count,
                    MAX(updated_at) AS updated_at
             FROM student_quizzes
             WHERE class_id = ? AND subject_id = ? AND quiz_number IS NOT NULL
             GROUP BY quiz_number"
        );
    }

    $stmt->execute([$classId, $subjectId]);
    $map = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $number = intval($row['number']);
        $map[$number] = [
            'total_marks' => $row['total_marks'] !== null ? floatval($row['total_marks']) : null,
            'student_count' => intval($row['student_count'] ?? 0),
            'graded_count' => intval($row['graded_count'] ?? 0),
            'updated_at' => $row['updated_at'] ?? null,
        ];
    }

    return $map;
}

function fetchClassAssessments($pdo, $kind, $classId, $subjectId) {
    ensureAssessmentSchema($pdo);

    $marksSummary = fetchAssessmentMarksSummary($pdo, $kind, $classId, $subjectId);

    if ($kind === 'assignment') {
        $sql = "SELECT a.id,
                       a.assignment_number AS number,
                       a.assignment_name AS name,
                       a.description,
                       a.deadline,
                       a.status,
                       a.plan_item_id,
                       a.completed_at,
                       pi.title AS plan_title,
                       pi.description AS plan_description,
                       pi.topic AS plan_topic,
                       pi.status AS plan_status,
                       pi.scheduled_for,
                       pi.status_changed_at,
                       pi.updated_at AS plan_updated_at
                FROM class_assignments a
                LEFT JOIN class_subject_plan_items pi ON pi.id = a.plan_item_id
                WHERE a.class_id = ? AND a.subject_id = ?
                ORDER BY a.deadline IS NULL, a.deadline ASC, a.assignment_number ASC";
    } else {
        $sql = "SELECT q.id,
                       q.quiz_number AS number,
                       q.quiz_name AS name,
                       q.description,
                       q.deadline,
                       q.status,
                       q.plan_item_id,
                       q.completed_at,
                       pi.title AS plan_title,
                       pi.description AS plan_description,
                       pi.topic AS plan_topic,
                       pi.status AS plan_status,
                       pi.scheduled_for,
                       pi.status_changed_at,
                       pi.updated_at AS plan_updated_at
                FROM class_quizzes q
                LEFT JOIN class_subject_plan_items pi ON pi.id = q.plan_item_id
                WHERE q.class_id = ? AND q.subject_id = ?
                ORDER BY q.deadline IS NULL, q.deadline ASC, q.quiz_number ASC";
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$classId, $subjectId]);

    $now = new DateTimeImmutable('now');
    $rows = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $number = isset($row['number']) ? intval($row['number']) : null;
        $deadlineRaw = $row['deadline'] ?? null;
        $fallback = $row['scheduled_for'] ?? null;
        $deadline = $deadlineRaw ?: $fallback;
        $status = $row['plan_status'] ?: ($row['status'] ?? 'scheduled');
        $isOverdue = false;

        if ($deadline && $status !== 'covered') {
            $deadlineDt = DateTime::createFromFormat('Y-m-d H:i:s', $deadline) ?: DateTime::createFromFormat('Y-m-d', $deadline);
            if ($deadlineDt instanceof DateTimeInterface) {
                if ($deadlineDt < $now) {
                    $isOverdue = true;
                }
            }
        }

        $summary = ($number !== null && isset($marksSummary[$number])) ? $marksSummary[$number] : null;

        $rows[] = [
            'id' => intval($row['id']),
            'kind' => $kind,
            'plan_item_id' => $row['plan_item_id'] ? intval($row['plan_item_id']) : null,
            'number' => $number,
            'title' => $row['plan_title'] ?: ($row['name'] ?? null),
            'description' => $row['plan_description'] ?: ($row['description'] ?? null),
            'topic' => $row['plan_topic'] ?? null,
            'deadline' => $deadline,
            'status' => $status,
            'is_overdue' => $isOverdue,
            'total_marks' => $summary['total_marks'] ?? null,
            'student_count' => $summary['student_count'] ?? null,
            'graded_count' => $summary['graded_count'] ?? null,
            'updated_at' => $summary['updated_at'] ?? ($row['plan_updated_at'] ?? null),
            'completed_at' => $row['completed_at'] ?? null,
        ];
    }

    return $rows;
}

function listClassAssessments($pdo, $requester) {
    $classId = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
    $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : 0;

    if ($classId <= 0 || $subjectId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'class_id and subject_id are required']);
        return;
    }

    $role = strtolower($requester['role'] ?? '');
    $canManage = canManagePlanner($pdo, $requester, $classId, $subjectId);
    $canViewOnly = !$canManage && in_array($role, ['student', 'parent', 'guardian'], true);

    if (!$canManage && !$canViewOnly) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    try {
        $assignments = fetchClassAssessments($pdo, 'assignment', $classId, $subjectId);
        $quizzes = fetchClassAssessments($pdo, 'quiz', $classId, $subjectId);

        echo json_encode([
            'success' => true,
            'class_id' => $classId,
            'subject_id' => $subjectId,
            'assignments' => $assignments,
            'quizzes' => $quizzes,
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch assessments: ' . $e->getMessage()]);
    }
}

function saveClassAssessment($pdo, $input, $requester, $kind) {
    ensureAssessmentSchema($pdo);

    $classId = isset($input['class_id']) ? intval($input['class_id']) : 0;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : 0;
    if ($classId <= 0 || $subjectId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'class_id and subject_id are required']);
        return;
    }

    if (!canManagePlanner($pdo, $requester, $classId, $subjectId)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    $allowedStatuses = ['scheduled', 'ready_for_verification', 'covered', 'deferred'];
    $status = isset($input['status']) ? trim((string)$input['status']) : 'scheduled';
    if (!in_array($status, $allowedStatuses, true)) {
        $status = 'scheduled';
    }

    $deadlineRaw = $input['deadline'] ?? ($input['scheduled_at'] ?? null);
    $deadline = normalizePlannerDateTime($deadlineRaw);

    $title = isset($input['title']) ? trim((string)$input['title']) : '';
    if ($title === '') {
        $title = null;
    }

    $description = isset($input['description']) ? trim((string)$input['description']) : '';
    if ($description === '') {
        $description = null;
    }

    $topic = null;
    if ($kind === 'quiz') {
        $topic = isset($input['topic']) ? trim((string)$input['topic']) : '';
        if ($topic === '') {
            $topic = null;
        }
    }

    $planItemId = isset($input['plan_item_id']) ? intval($input['plan_item_id']) : null;
    if ($planItemId !== null && $planItemId <= 0) {
        $planItemId = null;
    }

    $teacherAssignmentId = isset($input['teacher_assignment_id']) ? intval($input['teacher_assignment_id']) : null;
    if ($teacherAssignmentId !== null && $teacherAssignmentId <= 0) {
        $teacherAssignmentId = null;
    }

    $teacherUserId = null;
    if ($teacherAssignmentId !== null) {
        $teacherUserId = resolveAssignmentTeacherUserId($pdo, $teacherAssignmentId);
        if ($teacherUserId === null) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid teacher_assignment_id']);
            return;
        }
    }

    $createdBy = isset($requester['id']) ? intval($requester['id']) : null;
    if ($createdBy !== null && $createdBy <= 0) {
        $createdBy = null;
    }

    $id = isset($input['id']) ? intval($input['id']) : 0;
    $number = isset($input['number']) ? intval($input['number']) : 0;
    if ($number < 0) {
        $number = 0;
    }

    $table = $kind === 'assignment' ? 'class_assignments' : 'class_quizzes';
    $nameColumn = $kind === 'assignment' ? 'assignment_name' : 'quiz_name';
    $numberColumn = $kind === 'assignment' ? 'assignment_number' : 'quiz_number';

    $nameValue = $title;
    if ($nameValue === null) {
        $nameValue = $kind === 'assignment'
            ? ($description ?? 'Assignment')
            : ($topic ?? $description ?? 'Quiz');
    }

    try {
        $pdo->beginTransaction();

        $existingRow = null;
        if ($id > 0) {
            $stmt = $pdo->prepare("SELECT id, {$numberColumn} AS number FROM {$table} WHERE id = ? AND class_id = ? AND subject_id = ? LIMIT 1");
            $stmt->execute([$id, $classId, $subjectId]);
            $existingRow = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$existingRow) {
                $pdo->rollBack();
                http_response_code(404);
                echo json_encode(['error' => ucfirst($kind) . ' not found']);
                return;
            }
            $number = intval($existingRow['number']);
        } elseif ($number > 0) {
            $stmt = $pdo->prepare("SELECT id, {$numberColumn} AS number FROM {$table} WHERE class_id = ? AND subject_id = ? AND {$numberColumn} = ? LIMIT 1");
            $stmt->execute([$classId, $subjectId, $number]);
            $existingRow = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($existingRow) {
                $id = intval($existingRow['id']);
                $number = intval($existingRow['number']);
            }
        }

        if ($id > 0 || $existingRow) {
            $targetId = $id > 0 ? $id : intval($existingRow['id']);
            $sql = "UPDATE {$table}
                    SET {$nameColumn} = :name,
                        description = :description,
                        deadline = :deadline,
                        status = :status,
                        updated_at = NOW()
                        " . ($planItemId !== null ? ', plan_item_id = :plan_item_id' : '') .
                        ($teacherUserId !== null ? ', teacher_user_id = :teacher_user_id' : '') .
                    " WHERE id = :id";

            $stmt = $pdo->prepare($sql);
            $params = [
                ':name' => $nameValue,
                ':description' => $kind === 'quiz' ? ($topic ?? $description) : $description,
                ':deadline' => $deadline,
                ':status' => $status,
                ':id' => $targetId,
            ];
            if ($planItemId !== null) {
                $params[':plan_item_id'] = $planItemId;
            }
            if ($teacherUserId !== null) {
                $params[':teacher_user_id'] = $teacherUserId;
            }

            $stmt->execute($params);
            $pdo->commit();
            echo json_encode(['success' => true, 'id' => $targetId, 'number' => $number, 'updated' => true]);
            return;
        }

        if ($number <= 0) {
            $stmt = $pdo->prepare("SELECT COALESCE(MAX({$numberColumn}), 0) FROM {$table} WHERE class_id = ? AND subject_id = ?");
            $stmt->execute([$classId, $subjectId]);
            $number = intval($stmt->fetchColumn()) + 1;
        } else {
            $stmt = $pdo->prepare("SELECT 1 FROM {$table} WHERE class_id = ? AND subject_id = ? AND {$numberColumn} = ? LIMIT 1");
            $stmt->execute([$classId, $subjectId, $number]);
            if ($stmt->fetch()) {
                $pdo->rollBack();
                http_response_code(409);
                echo json_encode(['error' => ucfirst($kind) . ' number already exists']);
                return;
            }
        }

        $insertSql = "INSERT INTO {$table}
            (class_id, subject_id, {$numberColumn}, {$nameColumn}, description, deadline, status, plan_item_id, teacher_user_id, created_by_user_id, created_at, updated_at)
            VALUES (:class_id, :subject_id, :number, :name, :description, :deadline, :status, :plan_item_id, :teacher_user_id, :created_by, NOW(), NOW())";

        $stmt = $pdo->prepare($insertSql);
        $stmt->execute([
            ':class_id' => $classId,
            ':subject_id' => $subjectId,
            ':number' => $number,
            ':name' => $nameValue,
            ':description' => $kind === 'quiz' ? ($topic ?? $description) : $description,
            ':deadline' => $deadline,
            ':status' => $status,
            ':plan_item_id' => $planItemId,
            ':teacher_user_id' => $teacherUserId,
            ':created_by' => $createdBy,
        ]);

        $newId = intval($pdo->lastInsertId());
        $pdo->commit();
        echo json_encode(['success' => true, 'id' => $newId, 'number' => $number, 'created' => true]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save ' . $kind . ': ' . $e->getMessage()]);
    }
}

/**
 * Resolve class name by class_id.
 */
function resolveClassNameById($pdo, $classId) {
    $stmt = $pdo->prepare("SELECT name FROM classes WHERE id = ? LIMIT 1");
    $stmt->execute([$classId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row ? trim((string)$row['name']) : null;
}

/**
 * Get student user IDs for a given class_id by mapping to class name (best-effort).
 */
function getStudentUserIdsForClassId($pdo, $classId) {
    $className = resolveClassNameById($pdo, $classId);
    if ($className === null || $className === '') {
        return [];
    }
    $stmt = $pdo->prepare(
        "SELECT u.id AS user_id
         FROM users u
         JOIN students s ON s.user_id = u.id
         LEFT JOIN user_profiles up ON up.user_id = u.id
         WHERE up.class = ?"
    );
    $stmt->execute([$className]);
    $ids = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $uid = intval($row['user_id'] ?? 0);
        if ($uid > 0) { $ids[] = $uid; }
    }
    return $ids;
}

/**
 * Mirror planner item to per-student tables: student_assignments / student_quizzes.
 * Fast and idempotent approach: delete existing rows by plan_item_id, then bulk insert for current roster.
 */
function syncPlannerItemToStudentTables($pdo, $plan, $itemId, $itemType, $title, $topic, $description, $scheduledFor, $status, $assignmentNumber = null, $quizNumber = null) {
    $classId = intval($plan['class_id'] ?? 0);
    $subjectId = intval($plan['subject_id'] ?? 0);
    if ($classId <= 0 || $subjectId <= 0 || $itemId <= 0) {
        return;
    }

    $studentIds = getStudentUserIdsForClassId($pdo, $classId);
    if (empty($studentIds)) {
        return;
    }

    if ($itemType === 'assignment') {
        if (!is_int($assignmentNumber) && !ctype_digit((string)$assignmentNumber)) {
            return; // require a valid assignment number to mirror into student_assignments
        }
        $assignmentNumber = intval($assignmentNumber);
        // Remove old mirrors for this plan item
        $pdo->prepare("DELETE FROM student_assignments WHERE plan_item_id = ?")->execute([$itemId]);
        // Prepare insert
        $sql = "INSERT INTO student_assignments (class_id, subject_id, student_user_id, assignment_number, title, description, deadline, plan_item_id, coverage_status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())";
        $ins = $pdo->prepare($sql);
        $deadlineDate = $scheduledFor; 
        foreach ($studentIds as $sid) {
            $ins->execute([
                $classId,
                $subjectId,
                $sid,
                $assignmentNumber,
                ($title !== null && $title !== '') ? $title : null,
                ($description !== null && $description !== '') ? $description : null,
                $deadlineDate,
                $itemId,
                $status,
            ]);
        }
    } elseif ($itemType === 'quiz') {
        if (!is_int($quizNumber) && !ctype_digit((string)$quizNumber)) {
            return; // require a valid quiz number to mirror into student_quizzes
        }
        $quizNumber = intval($quizNumber);
        $pdo->prepare("DELETE FROM student_quizzes WHERE plan_item_id = ?")->execute([$itemId]);
        $sql = "INSERT INTO student_quizzes (class_id, subject_id, student_user_id, quiz_number, title, topic, scheduled_at, plan_item_id, coverage_status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())";
        $ins = $pdo->prepare($sql);
        $scheduledAt = $scheduledFor; 
        foreach ($studentIds as $sid) {
            $ins->execute([
                $classId,
                $subjectId,
                $sid,
                $quizNumber,
                ($title !== null && $title !== '') ? $title : null,
                ($topic !== null && $topic !== '') ? $topic : null,
                $scheduledAt,
                $itemId,
                $status,
            ]);
        }
    }
}

function getPlannerData($pdo, $requester) {
    $classId = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
    $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : 0;
    // ... rest of the code remains the same ...
    $teacherAssignmentId = isset($_GET['teacher_assignment_id']) ? intval($_GET['teacher_assignment_id']) : null;

    plannerLog('getPlannerData.request', [
        'class_id' => $classId,
        'subject_id' => $subjectId,
        'teacher_assignment_id' => $teacherAssignmentId,
        'requester_id' => $requester['id'] ?? null,
        'role' => $requester['role'] ?? null,
    ]);

    if ($classId <= 0 || $subjectId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'class_id and subject_id are required']);
        plannerLog('getPlannerData.invalid_input', ['class_id' => $classId, 'subject_id' => $subjectId]);
        return;
    }

    $role = strtolower($requester['role'] ?? '');
    $canManage = canManagePlanner($pdo, $requester, $classId, $subjectId);
    $canViewOnly = !$canManage && in_array($role, ['student', 'parent', 'guardian'], true);

    if (!$canManage && !$canViewOnly) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        plannerLog('getPlannerData.forbidden', [
            'class_id' => $classId,
            'subject_id' => $subjectId,
            'requester_id' => $requester['id'] ?? null,
            'role' => $role,
        ]);
        return;
    }

    $plan = fetchPlannerPlanByContext($pdo, $classId, $subjectId, $teacherAssignmentId);
    if ($plan) {
        if ($canManage) {
            autoAdvancePlannerStatuses($pdo, (int)$plan['id']);
        }
        $items = loadPlannerItems($pdo, (int)$plan['id']);
        plannerLog('getPlannerData.success', [
            'plan_id' => $plan['id'],
            'items_count' => count($items),
            'viewer_role' => $role,
            'can_manage' => $canManage,
        ]);
        echo json_encode([
            'success' => true,
            'plan' => $plan,
            'items' => $items,
        ]);
        return;
    }

    plannerLog('getPlannerData.no_plan', []);
    echo json_encode([
        'success' => true,
        'plan' => null,
        'items' => [],
    ]);
}

function savePlannerPlan($pdo, $input, $requester) {
    $planId = isset($input['plan_id']) ? intval($input['plan_id']) : 0;
    $classId = isset($input['class_id']) ? intval($input['class_id']) : 0;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : 0;
    $assignmentProvided = array_key_exists('teacher_assignment_id', $input);
    $teacherAssignmentId = $assignmentProvided && $input['teacher_assignment_id'] !== null
        ? intval($input['teacher_assignment_id'])
        : null;

    plannerLog('savePlannerPlan.call', [
        'input' => $input,
        'requester_id' => $requester['id'] ?? null,
        'role' => $requester['role'] ?? null,
    ]);

    if ($classId <= 0 || $subjectId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'class_id and subject_id are required']);
        plannerLog('savePlannerPlan.invalid_input', ['class_id' => $classId, 'subject_id' => $subjectId]);
        return;
    }

    if (!canManagePlanner($pdo, $requester, $classId, $subjectId)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        plannerLog('savePlannerPlan.forbidden', ['class_id' => $classId, 'subject_id' => $subjectId, 'requester_id' => $requester['id'] ?? null]);
        return;
    }

    $frequency = isset($input['frequency']) ? trim((string)$input['frequency']) : 'Custom';
    $allowedFrequencies = ['Daily', 'Weekly', 'Monthly', 'Custom'];
    if (!in_array($frequency, $allowedFrequencies, true)) {
        $frequency = 'Custom';
    }

    $singleDate = normalizePlannerDate($input['single_date'] ?? null);
    $rangeStart = normalizePlannerDate($input['range_start'] ?? null);
    $rangeEnd = normalizePlannerDate($input['range_end'] ?? null);
    $status = isset($input['status']) ? trim((string)$input['status']) : 'active';
    if (!in_array($status, ['active', 'archived'], true)) {
        $status = 'active';
    }
    $termLabel = isset($input['academic_term_label']) ? trim((string)$input['academic_term_label']) : null;
    if ($termLabel === '') {
        $termLabel = null;
    }

    $teacherUserId = null;
    $role = strtolower($requester['role'] ?? '');
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    if (in_array($role, ['admin', 'teacher'], true) && !$isSuperAdmin) {
        $teacherUserId = intval($requester['id'] ?? 0) ?: null;
    }

    if ($teacherUserId === null && $teacherAssignmentId) {
        $teacherUserId = resolveAssignmentTeacherUserId($pdo, $teacherAssignmentId);
    }

    try {
        if ($planId > 0) {
            $existing = fetchPlannerPlanRow($pdo, $planId);
            if (!$existing || intval($existing['class_id']) !== $classId || intval($existing['subject_id']) !== $subjectId) {
                http_response_code(404);
                echo json_encode(['error' => 'Plan not found']);
                plannerLog('savePlannerPlan.not_found', ['plan_id' => $planId, 'class_id' => $classId, 'subject_id' => $subjectId]);
                return;
            }

            if (!$assignmentProvided) {
                $teacherAssignmentId = $existing['teacher_assignment_id'];
            }
            if ($teacherUserId === null) {
                $teacherUserId = $existing['teacher_user_id'];
            }

            plannerLog('savePlannerPlan.update_start', [
                'plan_id' => $planId,
                'class_id' => $classId,
                'subject_id' => $subjectId,
                'teacher_user_id' => $teacherUserId,
                'assignment_id' => $teacherAssignmentId,
            ]);

            $sql = "UPDATE class_subject_plans
                    SET academic_term_label = :term,
                        frequency = :frequency,
                        single_date = :single_date,
                        range_start = :range_start,
                        range_end = :range_end,
                        status = :status,
                        teacher_user_id = :teacher_user_id,
                        teacher_assignment_id = :assignment_id,
                        updated_at = NOW()
                    WHERE id = :id";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                ':term' => $termLabel,
                ':frequency' => $frequency,
                ':single_date' => $singleDate,
                ':range_start' => $rangeStart,
                ':range_end' => $rangeEnd,
                ':status' => $status,
                ':teacher_user_id' => $teacherUserId,
                ':assignment_id' => $teacherAssignmentId,
                ':id' => $planId,
            ]);
            plannerLog('savePlannerPlan.update_success', ['plan_id' => $planId]);
            echo json_encode(['success' => true, 'plan_id' => $planId, 'updated' => true]);
            return;
        }

        plannerLog('savePlannerPlan.insert_start', [
            'class_id' => $classId,
            'subject_id' => $subjectId,
            'teacher_user_id' => $teacherUserId,
            'assignment_id' => $teacherAssignmentId,
        ]);

        $sql = "INSERT INTO class_subject_plans
                (class_id, subject_id, teacher_user_id, teacher_assignment_id, academic_term_label,
                 frequency, single_date, range_start, range_end,
                 status, created_at, updated_at)
                VALUES (:class_id, :subject_id, :teacher_user_id, :assignment_id, :term,
                        :frequency, :single_date, :range_start, :range_end,
                        :status, NOW(), NOW())";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            ':class_id' => $classId,
            ':subject_id' => $subjectId,
            ':teacher_user_id' => $teacherUserId,
            ':assignment_id' => $teacherAssignmentId,
            ':term' => $termLabel,
            ':frequency' => $frequency,
            ':single_date' => $singleDate,
            ':range_start' => $rangeStart,
            ':range_end' => $rangeEnd,
            ':status' => $status,
        ]);

        $newPlanId = intval($pdo->lastInsertId());
        plannerLog('savePlannerPlan.insert_success', ['plan_id' => $newPlanId]);
        echo json_encode(['success' => true, 'plan_id' => $newPlanId, 'created' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save planner plan: ' . $e->getMessage()]);
        plannerLog('savePlannerPlan.error', ['message' => $e->getMessage(), 'code' => $e->getCode()]);
    }
}

function upsertPlannerSessions($pdo, $planItemId, array $sessions) {
    $processedDates = [];
    $upsert = $pdo->prepare(
        "INSERT INTO class_subject_plan_sessions (plan_item_id, session_date, notes, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE notes = VALUES(notes), status = VALUES(status), updated_at = NOW()"
    );
    foreach ($sessions as $session) {
        $date = normalizePlannerDate($session['session_date'] ?? null);
        if (!$date) {
            continue;
        }
        $notes = isset($session['notes']) ? trim((string)$session['notes']) : null;
        if ($notes === '') {
            $notes = null;
        }
        $status = isset($session['status']) ? trim((string)$session['status']) : 'scheduled';
        if (!in_array($status, ['scheduled', 'covered', 'cancelled'], true)) {
            $status = 'scheduled';
        }
        $upsert->execute([$planItemId, $date, $notes, $status]);
        $processedDates[] = $date;
    }

    if (empty($processedDates)) {
        $stmt = $pdo->prepare("DELETE FROM class_subject_plan_sessions WHERE plan_item_id = ?");
        $stmt->execute([$planItemId]);
        return;
    }

    $placeholders = implode(',', array_fill(0, count($processedDates), '?'));
    $params = array_merge([$planItemId], $processedDates);
    $sql = "DELETE FROM class_subject_plan_sessions WHERE plan_item_id = ? AND session_date NOT IN ($placeholders)";
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
}

function savePlannerItem($pdo, $input, $requester) {
    $planId = isset($input['plan_id']) ? intval($input['plan_id']) : 0;
    $itemId = isset($input['id']) ? intval($input['id']) : 0;
    if ($planId <= 0 && $itemId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'plan_id or id is required']);
        plannerLog('savePlannerItem.invalid_input', ['plan_id' => $planId, 'item_id' => $itemId]);
        return;
    }

    plannerLog('savePlannerItem.call', [
        'input' => $input,
        'requester_id' => $requester['id'] ?? null,
        'role' => $requester['role'] ?? null,
    ]);

    $existingItem = null;
    if ($itemId > 0) {
        $existingItem = fetchPlannerPlanItem($pdo, $itemId);
        if (!$existingItem) {
            http_response_code(404);
            echo json_encode(['error' => 'Planner item not found']);
            plannerLog('savePlannerItem.not_found', ['item_id' => $itemId]);
            return;
        }
        $planId = intval($existingItem['plan_id']);
    }

    $plan = fetchPlannerPlanRow($pdo, $planId);
    if (!$plan) {
        http_response_code(404);
        echo json_encode(['error' => 'Planner plan not found']);
        plannerLog('savePlannerItem.plan_not_found', ['plan_id' => $planId, 'item_id' => $itemId]);
        return;
    }

    if (!canManagePlanner($pdo, $requester, intval($plan['class_id']), intval($plan['subject_id']))) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        plannerLog('savePlannerItem.forbidden', ['plan_id' => $planId, 'item_id' => $itemId, 'requester_id' => $requester['id'] ?? null]);
        return;
    }

    $itemType = isset($input['item_type']) ? strtolower(trim((string)$input['item_type'])) : ($existingItem['item_type'] ?? 'syllabus');
    if (!in_array($itemType, ['syllabus', 'assignment', 'quiz'], true)) {
        $itemType = $existingItem['item_type'] ?? 'syllabus';
    }

    $title = isset($input['title']) ? trim((string)$input['title']) : ($existingItem['title'] ?? null);
    if ($title === '') { $title = null; }

    $topic = isset($input['topic']) ? trim((string)$input['topic']) : ($existingItem['topic'] ?? null);
    if ($topic === '') { $topic = null; }

    $description = isset($input['description']) ? trim((string)$input['description']) : ($existingItem['description'] ?? null);
    if ($description === '') { $description = null; }

    $scheduledFor = array_key_exists('scheduled_for', $input)
        ? normalizePlannerDateTime($input['scheduled_for'])
        : ($existingItem['scheduled_for'] ?? null);

    $scheduledUntil = array_key_exists('scheduled_until', $input)
        ? normalizePlannerDateTime($input['scheduled_until'])
        : ($existingItem['scheduled_until'] ?? null);

    $status = isset($input['status'])
        ? trim((string)$input['status'])
        : ($existingItem['status'] ?? 'scheduled');
    $allowedStatuses = ['scheduled', 'ready_for_verification', 'covered', 'deferred'];
    if (!in_array($status, $allowedStatuses, true)) {
        $status = $existingItem['status'] ?? 'scheduled';
    }

    $verificationNotes = isset($input['verification_notes'])
        ? trim((string)$input['verification_notes'])
        : ($existingItem['verification_notes'] ?? null);
    if ($verificationNotes === '') { $verificationNotes = null; }

    $deferredTo = array_key_exists('deferred_to', $input)
        ? normalizePlannerDateTime($input['deferred_to'])
        : ($existingItem['deferred_to'] ?? null);
    if ($status !== 'deferred') {
        $deferredTo = null;
    } elseif (!$deferredTo && $scheduledFor) {
        $deferredTo = $scheduledFor;
    }

    $sessions = isset($input['sessions']) && is_array($input['sessions']) ? $input['sessions'] : [];

    try {
        $assignmentNumber = null;
        $quizNumber = null;

        if ($existingItem) {
            plannerLog('savePlannerItem.update_start', ['item_id' => $itemId, 'plan_id' => $planId]);
            $sql = "UPDATE class_subject_plan_items
                    SET item_type = :item_type,
                        title = :title,
                        topic = :topic,
                        description = :description,
                        scheduled_for = :scheduled_for,
                        scheduled_until = :scheduled_until,
                        status = :status,
                        status_changed_at = CASE WHEN status <> :status THEN NOW() ELSE status_changed_at END,
                        verification_notes = :verification_notes,
                        deferred_to = :deferred_to,
                        updated_at = NOW()
                    WHERE id = :id";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([
                ':item_type' => $itemType,
                ':title' => $title,
                ':topic' => $topic,
                ':description' => $description,
                ':scheduled_for' => $scheduledFor,
                ':scheduled_until' => $scheduledUntil,
                ':status' => $status,
                ':verification_notes' => $verificationNotes,
                ':deferred_to' => $deferredTo,
                ':id' => $itemId,
            ]);
            upsertPlannerSessions($pdo, $itemId, $sessions);
            if ($itemType === 'assignment') {
                [$assignmentNumber] = upsertClassAssignmentForPlanItem($pdo, $plan, $itemId, $title, $description, $scheduledFor, $status);
            } elseif ($itemType === 'quiz') {
                [$quizNumber] = upsertClassQuizForPlanItem($pdo, $plan, $itemId, $title, $topic, $scheduledFor, $status);
            }
            syncLinkedAssessmentCoverage($pdo, $itemId, $status);
            // Mirror to student_* tables for faster downstream usage
            syncPlannerItemToStudentTables($pdo, $plan, $itemId, $itemType, $title, $topic, $description, $scheduledFor, $status, $assignmentNumber, $quizNumber);
            plannerLog('savePlannerItem.update_success', ['item_id' => $itemId]);
            echo json_encode(['success' => true, 'item_id' => $itemId, 'updated' => true]);
            return;
        }

        plannerLog('savePlannerItem.insert_start', ['plan_id' => $planId]);
        $sql = "INSERT INTO class_subject_plan_items
                (plan_id, item_type, title, topic, description,
                 scheduled_for, scheduled_until, status, status_changed_at, verification_notes,
                 deferred_to, created_at, updated_at)
                VALUES
                (:plan_id, :item_type, :title, :topic, :description,
                 :scheduled_for, :scheduled_until, :status, NOW(), :verification_notes,
                 :deferred_to, NOW(), NOW())";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([
            ':plan_id' => $planId,
            ':item_type' => $itemType,
            ':title' => $title,
            ':topic' => $topic,
            ':description' => $description,
            ':scheduled_for' => $scheduledFor,
            ':scheduled_until' => $scheduledUntil,
            ':status' => $status,
            ':verification_notes' => $verificationNotes,
            ':deferred_to' => $deferredTo,
        ]);
        $newId = intval($pdo->lastInsertId());
        upsertPlannerSessions($pdo, $newId, $sessions);
        if ($itemType === 'assignment') {
            [$assignmentNumber] = upsertClassAssignmentForPlanItem($pdo, $plan, $newId, $title, $description, $scheduledFor, $status);
        } elseif ($itemType === 'quiz') {
            [$quizNumber] = upsertClassQuizForPlanItem($pdo, $plan, $newId, $title, $topic, $scheduledFor, $status);
        }
        syncLinkedAssessmentCoverage($pdo, $newId, $status);
        // Mirror to student_* tables for faster downstream usage
        syncPlannerItemToStudentTables($pdo, $plan, $newId, $itemType, $title, $topic, $description, $scheduledFor, $status, $assignmentNumber, $quizNumber);
        plannerLog('savePlannerItem.insert_success', ['item_id' => $newId, 'plan_id' => $planId]);
        echo json_encode(['success' => true, 'item_id' => $newId, 'created' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save planner item: ' . $e->getMessage()]);
        plannerLog('savePlannerItem.error', ['message' => $e->getMessage(), 'code' => $e->getCode()]);
    }
}

function updatePlannerItemStatus($pdo, $input, $requester) {
    $itemId = isset($input['id']) ? intval($input['id']) : 0;
    $status = isset($input['status']) ? trim((string)$input['status']) : '';
    if ($itemId <= 0 || $status === '') {
        http_response_code(400);
        echo json_encode(['error' => 'id and status are required']);
        plannerLog('updatePlannerItemStatus.invalid_input', ['item_id' => $itemId, 'status' => $status]);
        return;
    }

    plannerLog('updatePlannerItemStatus.call', ['input' => $input, 'requester_id' => $requester['id'] ?? null]);

    $item = fetchPlannerPlanItem($pdo, $itemId);
    if (!$item) {
        http_response_code(404);
        echo json_encode(['error' => 'Planner item not found']);
        plannerLog('updatePlannerItemStatus.not_found', ['item_id' => $itemId]);
        return;
    }

    if (!canManagePlanner($pdo, $requester, intval($item['class_id']), intval($item['subject_id']))) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        plannerLog('updatePlannerItemStatus.forbidden', ['item_id' => $itemId, 'requester_id' => $requester['id'] ?? null]);
        return;
    }

    $allowedStatuses = ['scheduled', 'ready_for_verification', 'covered', 'deferred'];
    if (!in_array($status, $allowedStatuses, true)) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid status value']);
        return;
    }

    $verificationNotes = isset($input['verification_notes']) ? trim((string)$input['verification_notes']) : null;
    if ($verificationNotes === '') { $verificationNotes = null; }

    $hasScheduledFor = array_key_exists('scheduled_for', $input);
    $scheduledFor = $hasScheduledFor ? normalizePlannerDateTime($input['scheduled_for']) : null;

    $hasScheduledUntil = array_key_exists('scheduled_until', $input);
    $scheduledUntil = $hasScheduledUntil ? normalizePlannerDateTime($input['scheduled_until']) : null;

    $deferredTo = array_key_exists('deferred_to', $input) ? normalizePlannerDateTime($input['deferred_to']) : ($status === 'deferred' ? ($scheduledFor ?: $item['scheduled_for']) : null);
    if ($status === 'deferred' && !$deferredTo) {
        http_response_code(400);
        echo json_encode(['error' => 'deferred_to or scheduled_for required when deferring']);
        return;
    }
    if ($status !== 'deferred') {
        $deferredTo = null;
    }

    $sets = ["status = :status", "status_changed_at = NOW()", "verification_notes = :verification_notes", "deferred_to = :deferred_to", "updated_at = NOW()"];
    $params = [
        ':status' => $status,
        ':verification_notes' => $verificationNotes,
        ':deferred_to' => $deferredTo,
        ':id' => $itemId,
    ];

    if ($hasScheduledFor) {
        $sets[] = "scheduled_for = :scheduled_for";
        $params[':scheduled_for'] = $scheduledFor;
    }
    if ($hasScheduledUntil) {
        $sets[] = "scheduled_until = :scheduled_until";
        $params[':scheduled_until'] = $scheduledUntil;
    }

    $sql = "UPDATE class_subject_plan_items SET " . implode(', ', $sets) . " WHERE id = :id";

    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        syncLinkedAssessmentCoverage($pdo, $itemId, $status);
        plannerLog('updatePlannerItemStatus.success', ['item_id' => $itemId, 'status' => $status]);
        echo json_encode(['success' => true, 'item_id' => $itemId, 'status' => $status]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update planner item status: ' . $e->getMessage()]);
        plannerLog('updatePlannerItemStatus.error', ['message' => $e->getMessage(), 'code' => $e->getCode()]);
    }
}

function deletePlannerItem($pdo, $requester) {
    $itemId = isset($_GET['id']) ? intval($_GET['id']) : 0;
    if ($itemId <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'id is required']);
        plannerLog('deletePlannerItem.invalid_input', ['item_id' => $itemId]);
        return;
    }

    plannerLog('deletePlannerItem.call', ['item_id' => $itemId, 'requester_id' => $requester['id'] ?? null]);

    $item = fetchPlannerPlanItem($pdo, $itemId);
    if (!$item) {
        http_response_code(404);
        echo json_encode(['error' => 'Planner item not found']);
        plannerLog('deletePlannerItem.not_found', ['item_id' => $itemId]);
        return;
    }

    if (!canManagePlanner($pdo, $requester, intval($item['class_id']), intval($item['subject_id']))) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        plannerLog('deletePlannerItem.forbidden', ['item_id' => $itemId, 'requester_id' => $requester['id'] ?? null]);
        return;
    }

    try {
        $pdo->beginTransaction();
        plannerLog('deletePlannerItem.tx_start', ['item_id' => $itemId]);
        $stmt = $pdo->prepare("UPDATE student_assignments SET plan_item_id = NULL, coverage_status = 'scheduled' WHERE plan_item_id = ?");
        $stmt->execute([$itemId]);
        $stmt = $pdo->prepare("UPDATE student_quizzes SET plan_item_id = NULL, coverage_status = 'scheduled' WHERE plan_item_id = ?");
        $stmt->execute([$itemId]);
        $del = $pdo->prepare("DELETE FROM class_subject_plan_items WHERE id = ?");
        $del->execute([$itemId]);
        $pdo->commit();
        plannerLog('deletePlannerItem.success', ['item_id' => $itemId]);
        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to delete planner item: ' . $e->getMessage()]);
        plannerLog('deletePlannerItem.error', ['message' => $e->getMessage(), 'code' => $e->getCode()]);
    }
}

/**
 * Teacher: get class attendance for a date
 * GET params: date (YYYY-MM-DD), class_name (required)
 */
function getClassAttendance($pdo, $requester) {
    if (!(($requester['role'] ?? '') === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 0)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    $date = isset($_GET['date']) ? (string)$_GET['date'] : '';
    $className = isset($_GET['class_name']) ? trim((string)$_GET['class_name']) : '';
    if ($date === '' || $className === '') {
        http_response_code(400);
        echo json_encode(['error' => 'date and class_name are required']);
        return;
    }
    try {
        $stmt = $pdo->prepare("SELECT id, attendance_date, class_name, student_user_id, status, remarks, taken_by, created_at, updated_at
                               FROM class_attendance
                               WHERE attendance_date = ? AND class_name = ?");
        $stmt->execute([$date, $className]);
        echo json_encode(['success' => true, 'attendance' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch class attendance: ' . $e->getMessage()]);
    }
}

/**
 * Teacher: record class attendance (upsert)
 * Body: { attendance_date: 'YYYY-MM-DD', class_name: string, entries: [{ student_user_id, status, remarks? }] }
 */
function recordClassAttendance($pdo, $input, $requester) {
    $role = strtolower($requester['role'] ?? '');
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    
    // Allow Teachers, Admins, and SuperAdmins to record student attendance
    if (!($role === 'teacher' || $role === 'admin' || $isSuperAdmin)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden: Only Teachers, Admins, and SuperAdmins can record student attendance']);
        return;
    }
    $date = isset($input['attendance_date']) ? (string)$input['attendance_date'] : '';
    $className = isset($input['class_name']) ? trim((string)$input['class_name']) : '';
    $entries = isset($input['entries']) && is_array($input['entries']) ? $input['entries'] : [];
    if ($date === '' || $className === '' || empty($entries)) {
        http_response_code(400);
        echo json_encode(['error' => 'attendance_date, class_name and entries are required']);
        return;
    }
    try {
        $pdo->beginTransaction();
        $sql = "INSERT INTO class_attendance (attendance_date, class_name, student_user_id, status, remarks, taken_by, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())
                ON DUPLICATE KEY UPDATE status = VALUES(status), remarks = VALUES(remarks), taken_by = VALUES(taken_by), updated_at = NOW()";
        $stmt = $pdo->prepare($sql);
        $affected = 0;
        foreach ($entries as $e) {
            $sid = isset($e['student_user_id']) ? intval($e['student_user_id']) : 0;
            $st  = isset($e['status']) ? strtolower(trim((string)$e['status'])) : '';
            if ($sid <= 0 || !in_array($st, ['present','absent','leave'])) { continue; }
            $rmk = array_key_exists('remarks', $e) ? (string)$e['remarks'] : null;
            $stmt->execute([$date, $className, $sid, $st, $rmk, intval($requester['id'])]);
            $affected += $stmt->rowCount();
        }
        $pdo->commit();
        echo json_encode(['success' => true, 'updated' => $affected]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to record attendance: ' . $e->getMessage()]);
    }
}

/**
 * Student Marks: fetch marks for class+subject+kind+number
 * GET params: class_id & subject_id OR level+class_name+subject_name, kind ('quiz'|'assignment'), number (int)
 */
function getStudentMarks($pdo) {
    $classId   = isset($_GET['class_id']) ? intval($_GET['class_id']) : null;
    $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : null;
    if (!$classId || !$subjectId) {
        list($classId, $subjectId) = resolveClassAndSubject($pdo, $_GET, true);
    }

    $kind = isset($_GET['kind']) ? strtolower(trim((string)$_GET['kind'])) : '';
    $number = isset($_GET['number']) ? intval($_GET['number']) : 0;

    if (!$classId || !$subjectId || !in_array($kind, ['quiz', 'assignment']) || $number <= 0) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing/invalid class/subject, kind, or number']);
        return;
    }

    try {
        if ($kind === 'assignment') {
            $sql = "SELECT sa.id,
                           sa.class_id,
                           sa.subject_id,
                           sa.student_user_id,
                           u.name  AS student_name,
                           u.email AS student_email,
                           'assignment' AS kind,
                           sa.assignment_number AS number,
                           sa.total_marks,
                           sa.obtained_marks,
                           sa.title,
                           sa.description,
                           sa.deadline,
                           sa.submitted_at,
                           sa.graded_at,
                           sa.graded_by,
                           sa.created_at,
                           sa.updated_at
                    FROM student_assignments sa
                    JOIN users u ON u.id = sa.student_user_id
                    WHERE sa.class_id = ? AND sa.subject_id = ? AND sa.assignment_number = ?
                    ORDER BY u.name";
            $params = [$classId, $subjectId, $number];
        } else { // quiz
            $sql = "SELECT sq.id,
                           sq.class_id,
                           sq.subject_id,
                           sq.student_user_id,
                           u.name  AS student_name,
                           u.email AS student_email,
                           'quiz' AS kind,
                           sq.quiz_number AS number,
                           sq.total_marks,
                           sq.obtained_marks,
                           sq.title,
                           sq.topic,
                           sq.scheduled_at,
                           sq.attempted_at,
                           sq.graded_at,
                           sq.graded_by,
                           sq.created_at,
                           sq.updated_at
                    FROM student_quizzes sq
                    JOIN users u ON u.id = sq.student_user_id
                    WHERE sq.class_id = ? AND sq.subject_id = ? AND sq.quiz_number = ?
                    ORDER BY u.name";
            $params = [$classId, $subjectId, $number];
        }

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'marks' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch marks: ' . $e->getMessage()]);
    }
}

/**
 * Search students by name or roll number (Admin/Super Admin only)
 * Body: { query: string, type: 'name'|'roll' }
 */
function searchStudents($pdo, $input) {
    $query = isset($input['query']) ? trim((string)$input['query']) : '';
    $type  = isset($input['type']) ? strtolower(trim((string)$input['type'])) : 'name';
    if ($query === '') {
        http_response_code(400);
        echo json_encode(['error' => 'query is required']);
        return;
    }
    $like = '%' . $query . '%';
    try {
        if ($type === 'roll') {
            $sql = "SELECT u.id, u.name, up.roll_number, up.class
                    FROM users u
                    JOIN students s ON s.user_id = u.id
                    LEFT JOIN user_profiles up ON up.user_id = u.id
                    WHERE up.roll_number LIKE ?
                    ORDER BY u.name
                    LIMIT 10";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$like]);
        } else {
            $sql = "SELECT u.id, u.name, up.roll_number, up.class
                    FROM users u
                    JOIN students s ON s.user_id = u.id
                    LEFT JOIN user_profiles up ON up.user_id = u.id
                    WHERE u.name LIKE ?
                    ORDER BY u.name
                    LIMIT 10";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$like]);
        }
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'students' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to search students: ' . $e->getMessage()]);
    }
}

/**
 * Students listing by class name (best-effort using user_profiles.class)
 * GET params: class_name (required), level (optional for info only)
 */
function getStudentsInClass($pdo) {
    $className = isset($_GET['class_name']) ? trim((string)$_GET['class_name']) : '';
    if ($className === '') {
        http_response_code(400);
        echo json_encode(['error' => 'class_name is required']);
        return;
    }
    try {
        $sql = "SELECT u.id, u.name, u.email, up.roll_number, up.class
                FROM users u
                JOIN students s ON s.user_id = u.id
                LEFT JOIN user_profiles up ON up.user_id = u.id
                WHERE (up.class = ? OR up.class IS NULL)
                ORDER BY u.name";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$className]);
        echo json_encode(['success' => true, 'students' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch students: ' . $e->getMessage()]);
    }
}

/**
 * Upsert marks for multiple students (Admin Teacher only)
 * Body: {
 *   class_id, subject_id OR level+class_name+subject_name,
 *   kind: 'quiz'|'assignment', number: int, total_marks: int,
 *   entries: [{ student_user_id: number, obtained_marks: number }]
 * }
 */
function upsertStudentMarks($pdo, $input, $requester) {
    // Authorization: Admin teacher only (DB role Admin AND is_super_admin=0)
    if (!(($requester['role'] ?? '') === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 0)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    // Resolve target
    $classId   = isset($input['class_id']) ? intval($input['class_id']) : null;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : null;
    if (!$classId || !$subjectId) {
        list($classId, $subjectId) = resolveClassAndSubject($pdo, $input, false);
    }
    $kind = isset($input['kind']) ? strtolower(trim((string)$input['kind'])) : '';
    $number = isset($input['number']) ? intval($input['number']) : 0;
    $totalMarks = isset($input['total_marks']) ? intval($input['total_marks']) : 0;
    $entries = isset($input['entries']) && is_array($input['entries']) ? $input['entries'] : [];
    if (!$classId || !$subjectId || !in_array($kind, ['quiz','assignment']) || $number <= 0 || $totalMarks <= 0 || empty($entries)) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing/invalid payload']);
        return;
    }

    $titleInput = isset($input['title']) ? trim((string)$input['title']) : null;
    if ($titleInput === '') { $titleInput = null; }
    $descriptionInput = isset($input['description']) ? trim((string)$input['description']) : null;
    if ($descriptionInput === '') { $descriptionInput = null; }
    $deadlineInput = isset($input['deadline']) ? trim((string)$input['deadline']) : null;
    if ($deadlineInput === '') { $deadlineInput = null; }
    $submittedAtInput = isset($input['submitted_at']) ? trim((string)$input['submitted_at']) : null;
    if ($submittedAtInput === '') { $submittedAtInput = null; }
    $scheduledAtInput = isset($input['scheduled_at']) ? trim((string)$input['scheduled_at']) : null;
    if ($scheduledAtInput === '') { $scheduledAtInput = null; }
    $attemptedAtInput = isset($input['attempted_at']) ? trim((string)$input['attempted_at']) : null;
    if ($attemptedAtInput === '') { $attemptedAtInput = null; }
    $gradedAtInput = isset($input['graded_at']) ? trim((string)$input['graded_at']) : null;
    if ($gradedAtInput === '') { $gradedAtInput = null; }
    $topicInput = isset($input['topic']) ? trim((string)$input['topic']) : null;
    if ($topicInput === '') { $topicInput = null; }

    try {
        $pdo->beginTransaction();

        if ($kind === 'assignment') {
            $check = $pdo->prepare("SELECT 1 FROM student_assignments WHERE class_id = ? AND subject_id = ? AND assignment_number = ? LIMIT 1");
            $check->execute([$classId, $subjectId, $number]);
            if ($check->fetch()) {
                $mx = $pdo->prepare("SELECT COALESCE(MAX(assignment_number), 0) AS maxnum FROM student_assignments WHERE class_id = ? AND subject_id = ?");
                $mx->execute([$classId, $subjectId]);
                $row = $mx->fetch(PDO::FETCH_ASSOC);
                $number = intval($row['maxnum']) + 1;
            }

            $sql = "INSERT INTO student_assignments (
                        class_id, subject_id, student_user_id, assignment_number,
                        title, description, total_marks, obtained_marks,
                        deadline, submitted_at, graded_at, graded_by
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $affected = 0;
            foreach ($entries as $e) {
                $sid = isset($e['student_user_id']) ? intval($e['student_user_id']) : 0;
                if ($sid <= 0) { continue; }
                $obt = isset($e['obtained_marks']) ? floatval($e['obtained_marks']) : null;
                if ($obt === null || $obt < 0) { continue; }

                $title = isset($e['title']) ? trim((string)$e['title']) : $titleInput;
                if ($title === '') { $title = null; }
                $desc = isset($e['description']) ? trim((string)$e['description']) : $descriptionInput;
                if ($desc === '') { $desc = null; }
                $deadline = isset($e['deadline']) ? trim((string)$e['deadline']) : $deadlineInput;
                if ($deadline === '') { $deadline = null; }
                $submittedAt = isset($e['submitted_at']) ? trim((string)$e['submitted_at']) : (isset($e['taken_at']) ? trim((string)$e['taken_at']) : $submittedAtInput);
                if ($submittedAt === '') { $submittedAt = null; }
                $gradedAt = isset($e['graded_at']) ? trim((string)$e['graded_at']) : $gradedAtInput;
                if ($gradedAt === '') { $gradedAt = null; }

                $params = [
                    $classId,
                    $subjectId,
                    $sid,
                    $number,
                    $title,
                    $desc,
                    $totalMarks,
                    $obt,
                    $deadline,
                    $submittedAt,
                    $gradedAt,
                    intval($requester['id'])
                ];

                $stmt->execute($params);
                $affected += $stmt->rowCount();
            }
        } else { // quiz
            $check = $pdo->prepare("SELECT 1 FROM student_quizzes WHERE class_id = ? AND subject_id = ? AND quiz_number = ? LIMIT 1");
            $check->execute([$classId, $subjectId, $number]);
            if ($check->fetch()) {
                $mx = $pdo->prepare("SELECT COALESCE(MAX(quiz_number), 0) AS maxnum FROM student_quizzes WHERE class_id = ? AND subject_id = ?");
                $mx->execute([$classId, $subjectId]);
                $row = $mx->fetch(PDO::FETCH_ASSOC);
                $number = intval($row['maxnum']) + 1;
            }

            $sql = "INSERT INTO student_quizzes (
                        class_id, subject_id, student_user_id, quiz_number,
                        title, topic, total_marks, obtained_marks,
                        scheduled_at, attempted_at, graded_at, graded_by
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
            $stmt = $pdo->prepare($sql);
            $affected = 0;
            foreach ($entries as $e) {
                $sid = isset($e['student_user_id']) ? intval($e['student_user_id']) : 0;
                if ($sid <= 0) { continue; }
                $obt = isset($e['obtained_marks']) ? floatval($e['obtained_marks']) : null;
                if ($obt === null || $obt < 0) { continue; }

                $title = isset($e['title']) ? trim((string)$e['title']) : $titleInput;
                if ($title === '') { $title = null; }
                $topic = isset($e['topic']) ? trim((string)$e['topic']) : $topicInput;
                if ($topic === '') { $topic = null; }
                $scheduled = isset($e['scheduled_at']) ? trim((string)$e['scheduled_at']) : $scheduledAtInput;
                if ($scheduled === '') { $scheduled = null; }
                $attempted = isset($e['attempted_at']) ? trim((string)$e['attempted_at']) : (isset($e['taken_at']) ? trim((string)$e['taken_at']) : $attemptedAtInput);
                if ($attempted === '') { $attempted = null; }
                $gradedAt = isset($e['graded_at']) ? trim((string)$e['graded_at']) : $gradedAtInput;
                if ($gradedAt === '') { $gradedAt = null; }

                $params = [
                    $classId,
                    $subjectId,
                    $sid,
                    $number,
                    $title,
                    $topic,
                    $totalMarks,
                    $obt,
                    $scheduled,
                    $attempted,
                    $gradedAt,
                    intval($requester['id'])
                ];

                $stmt->execute($params);
                $affected += $stmt->rowCount();
            }
        }

        $pdo->commit();
        echo json_encode(['success' => true, 'updated' => $affected]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to upsert marks: ' . $e->getMessage()]);
    }
}

/**
 * Map UI role labels to DB role + is_super_admin
 * - "Teacher" => role "Admin", is_super_admin = 0
 * - "Admin"   => role "Admin", is_super_admin = 1 (Super Admin)
 * - "Student" => role "Student", is_super_admin = 0
 */
function map_role_and_super($roleRaw) {
    $r = strtolower(trim((string)$roleRaw));
    switch ($r) {
        case 'teacher':
            return ['Admin', 0];
        case 'admin':
            return ['Admin', 1];
        case 'student':
        default:
            return ['Student', 0];
    }
}

/**
 * Return courses assigned to the authenticated teacher using teacher_courses mapping
 */
function getMyCourses($pdo, $requester) {
    $dbRole = strtolower($requester['role'] ?? '');
    $isSA   = intval($requester['is_super_admin'] ?? 0);
    $userId = $requester['id'] ?? null;
    if (!$userId) {
        http_response_code(401);
        echo json_encode(['error' => 'Unauthorized']);
        return;
    }

    // Treat Teacher-Admin (DB role Admin + is_super_admin=0) as teachers
    $isTeacher = ($dbRole === 'admin' && $isSA === 0);
    // Optionally, Super Admins can view none by default
    if (!$isTeacher) {
        echo json_encode(['success' => true, 'courses' => []]);
        return;
    }

    try {
        // Build from teacher_class_subject_assignments so each subject/class appears
        $sql = "SELECT 
                    a.id,
                    a.teacher_user_id,
                    c.id   AS class_id,
                    c.name AS class_name,
                    c.level AS level,
                    s.id   AS subject_id,
                    s.name AS subject_name,
                    -- Alias 'name' to match frontend expectations
                    CONCAT(s.name, ' - ', c.name) AS name
                FROM teacher_class_subject_assignments a
                JOIN classes c  ON c.id = a.class_id
                JOIN subjects s ON s.id = a.subject_id
                WHERE a.teacher_user_id = ?
                ORDER BY c.level, c.name, s.name";
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'courses' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch my courses: ' . $e->getMessage()]);
    }
}

/**
 * Settings: Term Start Date
 */
function getTermStart($pdo) {
    try {
        $stmt = $pdo->prepare("SELECT `value` FROM app_settings WHERE `key` = 'term_start_date' LIMIT 1");
        $stmt->execute();
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'term_start_date' => $row['value'] ?? null]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch term start: ' . $e->getMessage()]);
    }
}

/**
 * Notices: list and create
 */
function listNotices($pdo, $limit = 10) {
    try {
        $limit = max(1, min(100, intval($limit)));
        $stmt = $pdo->prepare("SELECT n.id, n.title, n.created_at, u.name AS author_name FROM notices n LEFT JOIN users u ON n.created_by = u.id ORDER BY n.created_at DESC LIMIT $limit");
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'notices' => $rows]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch notices: ' . $e->getMessage()]);
    }
}

function createNotice($pdo, $requester, $input) {
    $role = strtolower($requester['role'] ?? '');
    if (!in_array($role, ['teacher', 'principal', 'admin'])) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    $title = trim((string)($input['title'] ?? ''));
    $body  = isset($input['body']) ? (string)$input['body'] : null;
    if ($title === '') {
        http_response_code(400);
        echo json_encode(['error' => 'title is required']);
        return;
    }
    try {
        $stmt = $pdo->prepare("INSERT INTO notices (title, body, created_at, created_by) VALUES (?, ?, NOW(), ?)");
        $stmt->execute([$title, $body, $requester['id']]);
        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create notice: ' . $e->getMessage()]);
    }
}

function setTermStart($pdo, $input, $requester) {
    // Only Admins (including Super Admin) can set term start
    if (($requester['role'] ?? '') !== 'Admin') {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }
    if (!isset($input['term_start_date'])) {
        http_response_code(400);
        echo json_encode(['error' => 'term_start_date is required (YYYY-MM-DD)']);
        return;
    }
    $date = $input['term_start_date'];
    try {
        $stmt = $pdo->prepare("INSERT INTO app_settings (`key`, `value`, `updated_at`) VALUES ('term_start_date', ?, NOW()) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `updated_at` = NOW()");
        $stmt->execute([$date]);
        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to set term start: ' . $e->getMessage()]);
    }
}

/**
 * Attendance Records (simple per-user daily status) and Summary
 */
function upsertAttendanceRecord($pdo, $input, $requester) {
    $role = strtolower($requester['role'] ?? '');
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    $userId = intval($input['user_id'] ?? 0);
    
    // Get target user's role to determine permissions
    try {
        $stmt = $pdo->prepare("SELECT role FROM users WHERE id = ?");
        $stmt->execute([$userId]);
        $targetUser = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$targetUser) {
            http_response_code(404);
            echo json_encode(['error' => 'Target user not found']);
            return;
        }
        $targetRole = strtolower($targetUser['role'] ?? '');
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch target user: ' . $e->getMessage()]);
        return;
    }
    
    // Permission logic:
    // - SuperAdmin can take attendance for anyone (students, admins, teachers)
    // - Admin can take attendance for students and teachers, but NOT other admins
    // - Teachers can take attendance for students only
    if ($isSuperAdmin) {
        // SuperAdmin can record attendance for anyone
    } elseif ($role === 'admin') {
        // Admin can record attendance for students and teachers, but not other admins
        if ($targetRole === 'admin') {
            http_response_code(403);
            echo json_encode(['error' => 'Forbidden: Only SuperAdmin can record attendance for other Admins']);
            return;
        }
    } elseif ($role === 'teacher') {
        // Teachers can only record attendance for students
        if ($targetRole !== 'student') {
            http_response_code(403);
            echo json_encode(['error' => 'Forbidden: Teachers can only record attendance for Students']);
            return;
        }
    } else {
        // Students and other roles cannot record attendance for others
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden: Insufficient permissions']);
        return;
    }
    if (!isset($input['user_id']) || !isset($input['date']) || !isset($input['status'])) {
        http_response_code(400);
        echo json_encode(['error' => 'user_id, date (YYYY-MM-DD), and status are required']);
        return;
    }
    $userId = intval($input['user_id']);
    $date = $input['date'];
    $status = $input['status']; // expect present|absent|leave
    if (!in_array($status, ['present','absent','leave'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid status']);
        return;
    }
    try {
        $stmt = $pdo->prepare("INSERT INTO attendance_records (user_id, `date`, status, created_at, updated_at) VALUES (?, ?, ?, NOW(), NOW()) ON DUPLICATE KEY UPDATE status = VALUES(status), updated_at = NOW()");
        $stmt->execute([$userId, $date, $status]);
        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to upsert attendance record: ' . $e->getMessage()]);
    }
}

function getAttendanceSummary($pdo, $requester, $userId) {
    // Clean any output buffer
    if (ob_get_level()) {
        ob_clean();
    }
    
    // Set JSON header first
    header('Content-Type: application/json');
    
    // Authorization: Admin can only access their own record
    $role = strtolower($requester['role'] ?? '');
    $isSuperAdmin = intval($requester['is_super_admin'] ?? 0) === 1;
    $isAdmin = ($role === 'admin' || $isSuperAdmin);
    
    // Force admin to only see their own attendance record
    if ($isAdmin) {
        $userId = intval($requester['id']);
    } else if (intval($requester['id']) !== intval($userId)) {
        http_response_code(403);
        echo json_encode(['success' => false, 'error' => 'Forbidden']);
        return;
    }
    
    try {
        // Decide source table based on role
        $role = strtolower($requester['role'] ?? '');
        $useAdminTable = ($role === 'admin');
        $tableToCheck = $useAdminTable ? 'attendance_records' : 'class_attendance';
        // Check if chosen table exists
        $stmt = $pdo->prepare("SHOW TABLES LIKE '" . $tableToCheck . "'");
        $stmt->execute();
        if (!$stmt->fetch()) {
            echo json_encode(['success' => true, 'term_start_date' => null, 'present' => 0, 'absent' => 0, 'leave' => 0, 'total' => 0, 'percentages' => ['present' => 0, 'absent' => 0, 'leave' => 0]]);
            exit();
        }
        
        // Set default term start if app_settings doesn't exist
        $termStart = '2024-01-01';
        try {
            $stmt = $pdo->prepare("SELECT `value` FROM app_settings WHERE `key` = 'term_start_date' LIMIT 1");
            $stmt->execute();
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row) {
                $termStart = $row['value'];
            }
        } catch (PDOException $e) {
            // app_settings table doesn't exist, use default
        }
        
        $today = date('Y-m-d');

        // Aggregate counts between term start and today from selected source
        if ($useAdminTable) {
            $stmt2 = $pdo->prepare("SELECT status, COUNT(*) as cnt
                                    FROM attendance_records
                                    WHERE user_id = ? AND `date` BETWEEN ? AND ?
                                    GROUP BY status");
            $stmt2->execute([$userId, $termStart, $today]);
        } else {
            $stmt2 = $pdo->prepare("SELECT status, COUNT(*) as cnt
                                    FROM class_attendance
                                    WHERE student_user_id = ? AND attendance_date BETWEEN ? AND ?
                                    GROUP BY status");
            $stmt2->execute([$userId, $termStart, $today]);
        }
        $counts = ['present' => 0, 'absent' => 0, 'leave' => 0];
        foreach ($stmt2->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $st = strtolower(trim((string)$r['status']));
            if (!in_array($st, ['present','absent','leave'])) { continue; }
            $counts[$st] = (int)$r['cnt'];
        }
        $total = array_sum($counts);
        $perc = $total > 0 ? [
            'present' => round($counts['present'] * 100 / $total, 1),
            'absent'  => round($counts['absent'] * 100 / $total, 1),
            'leave'   => round($counts['leave'] * 100 / $total, 1),
        ] : ['present' => 0, 'absent' => 0, 'leave' => 0];

        echo json_encode([
            'success' => true,
            'term_start_date' => $termStart,
            'present' => $counts['present'],
            'absent' => $counts['absent'],
            'leave' => $counts['leave'],
            'total' => $total,
            'percentages' => $perc
        ]);
        exit();
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Database error: ' . $e->getMessage()]);
        exit();
    }
}

/**
 * Calendar: monthly fetch (holidays from calendar_dates + user events)
 */
function getCalendarMonthly($pdo, $year, $month) {
    try {
        // Holidays / titles from calendar_dates for that month
        $stmt1 = $pdo->prepare("SELECT `date`, `is_holiday`, `title` FROM calendar_dates WHERE `year` = ? AND `month` = ? ORDER BY `date`");
        $stmt1->execute([$year, $month]);
        $days = $stmt1->fetchAll(PDO::FETCH_ASSOC);

        // User events for the month
        $first = sprintf('%04d-%02d-01', $year, $month);
        $last = date('Y-m-t', strtotime($first));
        $stmt2 = $pdo->prepare("SELECT id, user_id, `date`, title, duration FROM calendar_user_events WHERE `date` BETWEEN ? AND ? ORDER BY `date`");
        $stmt2->execute([$first, $last]);
        $events = $stmt2->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode(['success' => true, 'days' => $days, 'events' => $events]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch calendar: ' . $e->getMessage()]);
    }
}

/**
 * Calendar: create event (role: Admin or Teacher)
 */
function createCalendarEvent($pdo, $input, $requester) {
    if (!isset($input['date']) || !isset($input['title'])) {
        http_response_code(400);
        echo json_encode(['error' => 'date and title are required']);
        return;
    }
    $role = $requester['role'] ?? '';
    $allowed = ($role === 'Admin' || $role === 'Teacher');
    if (!$allowed) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    $userId = (int)$requester['id'];
    $date = $input['date']; // YYYY-MM-DD
    $title = trim($input['title']);
    $duration = isset($input['duration']) ? trim($input['duration']) : null;

    try {
        $stmt = $pdo->prepare("INSERT INTO calendar_user_events (user_id, `date`, title, duration, created_at) VALUES (?, ?, ?, ?, NOW())");
        $stmt->execute([$userId, $date, $title, $duration]);
        echo json_encode(['success' => true, 'event_id' => $pdo->lastInsertId()]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create event: ' . $e->getMessage()]);
    }
}

/**
 * Resolve class_id and subject_id from either IDs or names.
 * For GET, reads from $_GET; for POST, pass $input array.
 * Accepts keys: class_id, subject_id OR level + class_name + subject_name.
 * Returns [class_id, subject_id] or [null, null] if not resolvable.
 */
function resolveClassAndSubject($pdo, $source, $isGet = true) {
    $get = function($k) use ($source, $isGet) {
        return $isGet ? ($source[$k] ?? null) : ($source[$k] ?? null);
    };

    $classId   = isset($source['class_id']) ? intval($source['class_id']) : null;
    $subjectId = isset($source['subject_id']) ? intval($source['subject_id']) : null;

    if ($classId && $subjectId) {
        return [$classId, $subjectId];
    }

    $levelRaw    = isset($source['level']) ? (string)$source['level'] : null;
    $className   = isset($source['class_name']) ? (string)$source['class_name'] : null;
    $subjectName = isset($source['subject_name']) ? (string)$source['subject_name'] : null;
    if (!$levelRaw || !$className || !$subjectName) {
        return [null, null];
    }
    $level = normalize_level($levelRaw);
    if (!$level) return [null, null];

    try {
        // Resolve class
        $stmt = $pdo->prepare("SELECT id FROM classes WHERE level = ? AND name = ? LIMIT 1");
        $stmt->execute([$level, $className]);
        $c = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$c) return [null, null];
        $classId = intval($c['id']);

        // Resolve subject
        $stmt2 = $pdo->prepare("SELECT id FROM subjects WHERE level = ? AND name = ? LIMIT 1");
        $stmt2->execute([$level, $subjectName]);
        $s = $stmt2->fetch(PDO::FETCH_ASSOC);
        if (!$s) return [null, null];
        $subjectId = intval($s['id']);

        return [$classId, $subjectId];
    } catch (PDOException $e) {
        return [null, null];
    }
}

/**
 * GET /course_summary
 * Query params: class_id & subject_id OR level, class_name, subject_name
 * Returns today_topics and revise_topics along with other meta (if available).
 */
function getCourseSummary($pdo) {
    // Prefer IDs; fallback to name resolution
    $classId   = isset($_GET['class_id']) ? intval($_GET['class_id']) : null;
    $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : null;
    if (!$classId || !$subjectId) {
        list($classId, $subjectId) = resolveClassAndSubject($pdo, $_GET, true);
    }
    if (!$classId || !$subjectId) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing or invalid class/subject identifiers']);
        return;
    }
    try {
        // Include optional columns if present
        $hasDeadline = false;
        $hasNextAssignmentNumber = false;
        $hasLastQuizTaken = false;
        $hasLastQuizNumber = false;
        $hasNextQuizTopic = false;
        $hasLastAssignmentTaken = false;
        $hasLastAssignmentNumber = false;
        try {
            $hasDeadline = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'next_assignment_deadline'")->rowCount() > 0;
        } catch (Exception $ign) { $hasDeadline = false; }
        try {
            $hasNextAssignmentNumber = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'next_assignment_number'")->rowCount() > 0;
        } catch (Exception $ign) { $hasNextAssignmentNumber = false; }
        try {
            $hasLastQuizTaken = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'last_quiz_taken_at'")->rowCount() > 0;
        } catch (Exception $ign) { $hasLastQuizTaken = false; }
        try {
            $hasLastQuizNumber = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'last_quiz_number'")->rowCount() > 0;
        } catch (Exception $ign) { $hasLastQuizNumber = false; }
        try {
            $hasNextQuizTopic = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'next_quiz_topic'")->rowCount() > 0;
        } catch (Exception $ign) { $hasNextQuizTopic = false; }
        try {
            $hasLastAssignmentTaken = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'last_assignment_taken_at'")->rowCount() > 0;
        } catch (Exception $ign) { $hasLastAssignmentTaken = false; }
        try {
            $hasLastAssignmentNumber = $pdo->query("SHOW COLUMNS FROM course_meta LIKE 'last_assignment_number'")->rowCount() > 0;
        } catch (Exception $ign) { $hasLastAssignmentNumber = false; }

        $select = "class_id, subject_id, upcoming_lecture_at, next_quiz_at, next_assignment_url, total_lectures, lectures_json, today_topics, revise_topics, updated_by, updated_at" .
                  ($hasDeadline ? ", next_assignment_deadline" : "") .
                  ($hasNextAssignmentNumber ? ", next_assignment_number" : "") .
                  ($hasLastQuizTaken ? ", last_quiz_taken_at" : "") .
                  ($hasLastQuizNumber ? ", last_quiz_number" : "") .
                  ($hasNextQuizTopic ? ", next_quiz_topic" : "") .
                  ($hasLastAssignmentTaken ? ", last_assignment_taken_at" : "") .
                  ($hasLastAssignmentNumber ? ", last_assignment_number" : "");
        $stmt = $pdo->prepare("SELECT $select FROM course_meta WHERE class_id = ? AND subject_id = ? ORDER BY updated_at DESC LIMIT 1");
        $stmt->execute([$classId, $subjectId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            echo json_encode([
                'success' => true,
                'meta' => [
                    'class_id' => $classId,
                    'subject_id' => $subjectId,
                    'today_topics' => null,
                    'revise_topics' => null,
                    'upcoming_lecture_at' => null,
                    'next_quiz_at' => null,
                    'next_assignment_url' => null,
                    'next_assignment_deadline' => $hasDeadline ? null : null,
                    'next_assignment_number' => $hasNextAssignmentNumber ? null : null,
                    'next_quiz_topic' => $hasNextQuizTopic ? null : null,
                    'last_quiz_taken_at' => $hasLastQuizTaken ? null : null,
                    'last_quiz_number' => $hasLastQuizNumber ? null : null,
                    'total_lectures' => 0,
                    'lectures_json' => null,
                    'updated_by' => null,
                    'updated_at' => null,
                    'last_assignment_taken_at' => $hasLastAssignmentTaken ? null : null,
                    'last_assignment_number' => $hasLastAssignmentNumber ? null : null,
                ]
            ]);
            return;
        }
        echo json_encode(['success' => true, 'meta' => $row]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch course summary: ' . $e->getMessage()]);
    }
}

/**
 * POST /course_summary
 * Body: { class_id, subject_id } OR { level, class_name, subject_name }
 *        today_topics?: string, revise_topics?: string
 * Only Admin teachers (role=Admin, is_super_admin=0) can write.
 */
function saveCourseSummary($pdo, $input, $requester) {
    // Authorization: Admin teacher only (DB role Admin AND is_super_admin=0)
    if (!(($requester['role'] ?? '') === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 0)) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    // Resolve target
    $classId   = isset($input['class_id']) ? intval($input['class_id']) : null;
    $subjectId = isset($input['subject_id']) ? intval($input['subject_id']) : null;
    if (!$classId || !$subjectId) {
        list($classId, $subjectId) = resolveClassAndSubject($pdo, $input, false);
    }
    if (!$classId || !$subjectId) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing or invalid class/subject identifiers']);
        return;
    }

    $today  = array_key_exists('today_topics', $input) ? (string)$input['today_topics'] : null;
    $revise = array_key_exists('revise_topics', $input) ? (string)$input['revise_topics'] : null;
    $upcomingLectureAt = array_key_exists('upcoming_lecture_at', $input) ? (string)$input['upcoming_lecture_at'] : null;
    $nextQuizAt        = array_key_exists('next_quiz_at', $input) ? (string)$input['next_quiz_at'] : null;
    $nextAssignUrl     = array_key_exists('next_assignment_url', $input) ? (string)$input['next_assignment_url'] : null;
    $totalLectures     = array_key_exists('total_lectures', $input) ? (int)$input['total_lectures'] : null;
    $lecturesJson      = array_key_exists('lectures_json', $input) ? (string)$input['lectures_json'] : null;
    // Optional: assignment deadline & quiz/assignment tracking if schema includes them
    $nextAssignDeadline = array_key_exists('next_assignment_deadline', $input) ? (string)$input['next_assignment_deadline'] : null;
    $nextAssignmentNumber = array_key_exists('next_assignment_number', $input) ? (int)$input['next_assignment_number'] : null;
    $nextQuizTopic     = array_key_exists('next_quiz_topic', $input) ? (string)$input['next_quiz_topic'] : null;
    $lastQuizTakenAt    = array_key_exists('last_quiz_taken_at', $input) ? (string)$input['last_quiz_taken_at'] : null;
    $lastQuizNumber     = array_key_exists('last_quiz_number', $input) ? (int)$input['last_quiz_number'] : null;
    $lastAssignmentTakenAt = array_key_exists('last_assignment_taken_at', $input) ? (string)$input['last_assignment_taken_at'] : null;
    $lastAssignmentNumber  = array_key_exists('last_assignment_number', $input) ? (int)$input['last_assignment_number'] : null;

    try {
        // Helper to check if an optional column exists
        $hasCol = function(string $col) use ($pdo): bool {
            $q = $pdo->query("SHOW COLUMNS FROM course_meta LIKE '" . str_replace("'", "''", $col) . "'");
            return $q && $q->rowCount() > 0;
        };

        // Base columns and placeholders
        $columns = [
            'class_id', 'subject_id',
            'today_topics', 'revise_topics',
            'upcoming_lecture_at', 'next_quiz_at',
            'next_assignment_url', 'total_lectures',
            'lectures_json', 'updated_by', 'updated_at'
        ];
        $placeholders = ['?', '?', '?', '?', '?', '?', '?', '?', '?', '?', 'NOW()'];
        $params = [
            $classId, $subjectId,
            $today, $revise,
            $upcomingLectureAt, $nextQuizAt,
            $nextAssignUrl, $totalLectures,
            $lecturesJson, intval($requester['id'])
        ];

        // Optional columns
        if ($hasCol('next_assignment_deadline')) {
            $columns[] = 'next_assignment_deadline';
            $placeholders[] = '?';
            $params[] = $nextAssignDeadline;
        }
        if ($hasCol('next_assignment_number')) {
            $columns[] = 'next_assignment_number';
            $placeholders[] = '?';
            $params[] = $nextAssignmentNumber;
        }
        if ($hasCol('next_quiz_topic')) {
            $columns[] = 'next_quiz_topic';
            $placeholders[] = '?';
            $params[] = $nextQuizTopic;
        }
        if ($hasCol('last_quiz_taken_at')) {
            $columns[] = 'last_quiz_taken_at';
            $placeholders[] = '?';
            $params[] = $lastQuizTakenAt;
        }
        if ($hasCol('last_quiz_number')) {
            $columns[] = 'last_quiz_number';
            $placeholders[] = '?';
            $params[] = $lastQuizNumber;
        }
        if ($hasCol('last_assignment_taken_at')) {
            $columns[] = 'last_assignment_taken_at';
            $placeholders[] = '?';
            $params[] = $lastAssignmentTakenAt;
        }
        if ($hasCol('last_assignment_number')) {
            $columns[] = 'last_assignment_number';
            $placeholders[] = '?';
            $params[] = $lastAssignmentNumber;
        }

        // Build SQL safely
        $sql = 'INSERT INTO course_meta (' . implode(', ', $columns) . ') VALUES (' . implode(', ', $placeholders) . ')';
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        echo json_encode(['success' => true]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save course summary: ' . $e->getMessage()]);
    }
}

// Database configuration
$host = 'localhost';
$dbname = 'flutter_api';
$username = 'root';
$password = '';

try {
    // Create PDO connection
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch(PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database connection failed: ' . $e->getMessage()]);
    exit();
}

// ======================
// JWT Auth Configuration
// ======================
// In production, move this to a non-public config include and keep it secret.
$JWT_SECRET = 'change_this_secret_in_production_please';

function base64url_encode($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function base64url_decode($data) {
    return base64_decode(strtr($data, '-_', '+/'));
}

function jwt_encode($payload, $secret) {
    $header = ['alg' => 'HS256', 'typ' => 'JWT'];
    $segments = [
        base64url_encode(json_encode($header)),
        base64url_encode(json_encode($payload))
    ];
    $signing_input = implode('.', $segments);
    $signature = hash_hmac('sha256', $signing_input, $secret, true);
    $segments[] = base64url_encode($signature);
    return implode('.', $segments);
}

function jwt_decode($jwt, $secret) {
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) return false;
    list($h, $p, $s) = $parts;
    $payload = json_decode(base64url_decode($p), true);
    $sig = base64url_decode($s);
    $valid = hash_equals($sig, hash_hmac('sha256', "$h.$p", $secret, true));
    if (!$valid) return false;
    if (isset($payload['exp']) && time() >= $payload['exp']) return false;
    return $payload;
}

function get_bearer_token() {
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (preg_match('/Bearer\s+(.*)$/i', $auth, $m)) {
        return trim($m[1]);
    }
    return null;
}

/**
 * Normalize education level input from UI into DB enum values
 * Accepts variants like: "Early Years", "earlyyears", "EarlyYears" etc.
 * Returns one of: EarlyYears | Primary | Secondary, or null if invalid
 */
function normalize_level($raw) {
    if (!isset($raw)) return null;
    // Lowercase, remove spaces/underscores for tolerant matching
    $r = strtolower(trim((string)$raw));
    $r = str_replace([' ', '_', '-'], '', $r);
    switch ($r) {
        case 'earlyyears':
        case 'earlyyear':
        case 'ey':
            return 'EarlyYears';
        case 'primary':
        case 'pri':
            return 'Primary';
        case 'secondary':
        case 'sec':
            return 'Secondary';
        default:
            return null;
    }
}

/**
 * Compute synthetic role and is_super_admin from role tables.
 * Returns ['role' => 'Admin'|'Student', 'is_super_admin' => 0|1]
 */
function compute_role($pdo, $userId) {
    // Check Admins (may be super admin)
    $stmt = $pdo->prepare("SELECT is_super_admin FROM admins WHERE user_id = ? LIMIT 1");
    $stmt->execute([$userId]);
    $adm = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($adm) {
        return ['role' => 'Admin', 'is_super_admin' => intval($adm['is_super_admin'])];
    }
    // Check Teachers (treated as Admin with is_super_admin=0 for backward compatibility)
    $stmt = $pdo->prepare("SELECT 1 FROM teachers WHERE user_id = ? LIMIT 1");
    $stmt->execute([$userId]);
    if ($stmt->fetch()) {
        return ['role' => 'Admin', 'is_super_admin' => 0];
    }
    // Default to Student if present in students table; otherwise Student
    $stmt = $pdo->prepare("SELECT 1 FROM students WHERE user_id = ? LIMIT 1");
    $stmt->execute([$userId]);
    if ($stmt->fetch()) {
        return ['role' => 'Student', 'is_super_admin' => 0];
    }
    return ['role' => 'Student', 'is_super_admin' => 0];
}

function requireAuth($pdo, $JWT_SECRET) {
    $token = get_bearer_token();
    if (!$token) {
        http_response_code(401);
        echo json_encode(['error' => 'Missing bearer token']);
        exit();
    }
    $claims = jwt_decode($token, $JWT_SECRET);
    if (!$claims) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid or expired token']);
        exit();
    }
    // Optionally refresh requester from DB and compute role
    try {
        $stmt = $pdo->prepare("SELECT id, name, email FROM users WHERE id = ?");
        $stmt->execute([$claims['sub']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) {
            http_response_code(401);
            echo json_encode(['error' => 'User not found']);
            exit();
        }
        $r = compute_role($pdo, $user['id']);
        $user['role'] = $r['role'];
        $user['is_super_admin'] = $r['is_super_admin'];
        return $user;
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Auth failed: ' . $e->getMessage()]);
        exit();
    }
}

// Get request method and endpoint
$method = $_SERVER['REQUEST_METHOD'];
$endpoint = isset($_GET['endpoint']) ? $_GET['endpoint'] : '';

// Route the request based on method and endpoint
switch ($method) {
    case 'GET':
        handleGetRequest($endpoint, $pdo);
        break;
    case 'POST':
        handlePostRequest($endpoint, $pdo);
        break;
    case 'PUT':
        handlePutRequest($endpoint, $pdo);
        break;
    case 'DELETE':
        handleDeleteRequest($endpoint, $pdo);
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
}

/**
 * Handle GET requests
 */
function handleGetRequest($endpoint, $pdo) {
    switch ($endpoint) {
      case 'class_subject':
        // No GET handler for class_subject
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
      // no GET handler for 'class_subject' here
        case 'challan_list':
            // List challans (Admin: all, Student: own)
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            listChallans($pdo, $requester);
            break;
        case 'teachers':
            // List teachers (role Admin but not super admin)
            try {
                $stmt = $pdo->prepare("SELECT u.id, u.name, u.email
                                       FROM teachers t JOIN users u ON u.id = t.user_id
                                       ORDER BY u.name");
                $stmt->execute();
                $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
                echo json_encode(['success' => true, 'teachers' => $rows]);
            } catch (PDOException $e) {
                http_response_code(500);
                echo json_encode(['error' => 'Failed to fetch teachers: ' . $e->getMessage()]);
            }
            break;
        case 'download_assignment':
            // Public GET download by submission_id (no auth header required)
            $submissionId = isset($_GET['submission_id']) ? intval($_GET['submission_id']) : 0;
            if ($submissionId <= 0) {
                http_response_code(400);
                echo json_encode(['error' => 'Missing submission_id']);
                return;
            }
            try {
                $stmt = $pdo->prepare("SELECT s.*, u.name as student_name FROM assignment_submissions s JOIN users u ON u.id = s.student_id WHERE s.id = ?");
                $stmt->execute([$submissionId]);
                $submission = $stmt->fetch(PDO::FETCH_ASSOC);
                if (!$submission) {
                    http_response_code(404);
                    echo json_encode(['error' => 'Submission not found']);
                    return;
                }
                if (($submission['submission_type'] ?? '') === 'link') {
                    echo json_encode(['success' => true, 'type' => 'link', 'url' => $submission['file_name']]);
                    return;
                }
                $baseDir = defined('ASSIGNMENTS_UPLOAD_DIR') ? ASSIGNMENTS_UPLOAD_DIR : (__DIR__ . '/uploads/assignments');
                $filePath = rtrim($baseDir, '/\\') . '/' . basename($submission['file_name']);
                if (!file_exists($filePath)) {
                    // Fallback: try timestamped variant if DB has original name
                    $orig = basename($submission['file_name']);
                    $ext = pathinfo($orig, PATHINFO_EXTENSION);
                    $base = pathinfo($orig, PATHINFO_FILENAME);
                    $pattern = rtrim($baseDir, '/\\') . '/' . $base . '_*' . ($ext ? ('.' . $ext) : '');
                    $matches = glob($pattern);
                    if ($matches && count($matches) > 0) {
                        // Pick the most recent by modification time
                        usort($matches, function($a, $b){ return filemtime($b) <=> filemtime($a); });
                        $filePath = $matches[0];
                    } else {
                        http_response_code(404);
                        echo json_encode(['error' => 'File not found on server']);
                        return;
                    }
                }
                // Stream file
                $ctype = $submission['file_type'] ?: 'application/octet-stream';
                header('Content-Type: ' . $ctype);
                header('Content-Disposition: attachment; filename="' . basename($submission['file_name']) . '"');
                header('Content-Length: ' . filesize($filePath));
                readfile($filePath);
                exit;
            } catch (Exception $e) {
                http_response_code(500);
                echo json_encode(['error' => 'Failed to download: ' . $e->getMessage()]);
            }
            break;
        case 'classes':
          $levelRaw = isset($_GET['level']) ? (string)$_GET['level'] : '';
          $level = normalize_level($levelRaw);
          if (!$level) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid or missing level']);
            return;
          }
          try {
            $stmt = $pdo->prepare("SELECT id, level, name FROM classes WHERE level = ? ORDER BY name");
            $stmt->execute([$level]);
            echo json_encode(['success' => true, 'classes' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch classes: ' . $e->getMessage()]);
          }
          break;
        case 'teacher_classes':
          // Auth: Teacher only (Admin role, not SA)
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getTeacherClasses($pdo, $requester);
          break;
        case 'class_students_teacher':
          // Auth: Teacher only, and must be assigned to the class
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getClassStudentsForTeacher($pdo, $requester);
          break;
        case 'class_attendance':
          // Auth: Teacher only
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getClassAttendance($pdo, $requester);
          break;
        case 'class_attendance_history':
          // Auth: Teacher only
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getClassAttendanceHistory($pdo, $requester);
          break;
        case 'serve_file':
          // Serve uploaded files securely via GET (for displaying images)
          $fileName = isset($_GET['file']) ? $_GET['file'] : '';
          if (empty($fileName)) {
            http_response_code(400);
            echo json_encode(['error' => 'No file specified']);
            return;
          }

          // Validate file name to prevent directory traversal
          if (strpos($fileName, '..') !== false || strpos($fileName, '/') !== false || strpos($fileName, '\\') !== false) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid file name']);
            return;
          }

          $filePath = USER_FILES_UPLOAD_DIR . '/' . $fileName;
          if (!file_exists($filePath)) {
            // Fallback: try via DOCUMENT_ROOT mapping (e.g., Apache doc root)
            $docRoot = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/\\');
            if (!empty($docRoot)) {
              $altPath = $docRoot . '/backend/uploads/user_files/' . $fileName;
              if (file_exists($altPath)) {
                $filePath = $altPath;
              }
            }
          }
          if (!file_exists($filePath)) {
            @error_log('[serve_file][GET] File not found at: ' . $filePath . ' | original=' . (USER_FILES_UPLOAD_DIR . '/' . $fileName));
            http_response_code(404);
            echo json_encode(['error' => 'File not found']);
            return;
          }

          $mimeType = mime_content_type($filePath);
          if (strpos($mimeType, 'image/') === 0) {
            header('Content-Type: ' . $mimeType);
            header('Content-Length: ' . filesize($filePath));
            header('Cache-Control: public, max-age=3600');
            readfile($filePath);
          } else {
            http_response_code(400);
            echo json_encode(['error' => 'File type not supported']);
          }
          return; // Do not fall through to default
        case 'subjects':
          $levelRaw = isset($_GET['level']) ? (string)$_GET['level'] : '';
          $level = normalize_level($levelRaw);
          if (!$level) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid or missing level']);
            return;
          }
          try {
            $stmt = $pdo->prepare("SELECT id, level, name FROM subjects WHERE level = ? ORDER BY name");
            $stmt->execute([$level]);
            echo json_encode(['success' => true, 'subjects' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch subjects: ' . $e->getMessage()]);
          }
          break;
        case 'subject_search':
          // Search subjects by level and partial name
          $levelRaw = isset($_GET['level']) ? (string)$_GET['level'] : '';
          $q = isset($_GET['q']) ? trim((string)$_GET['q']) : '';
          $level = normalize_level($levelRaw);
          if (!$level || $q === '') { echo json_encode(['success' => true, 'subjects' => []]); return; }
          try {
            $limit = isset($_GET['limit']) ? max(1, min(50, intval($_GET['limit']))) : 20;
            $like = '%' . $q . '%';
            $stmt = $pdo->prepare("SELECT id, name FROM subjects WHERE level = ? AND name LIKE ? ORDER BY name LIMIT $limit");
            $stmt->execute([$level, $like]);
            echo json_encode(['success' => true, 'subjects' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Search failed: ' . $e->getMessage()]);
          }
          break;
        case 'class_subjects':
          // List subjects linked to a class (using class_subjects join table)
          $levelRaw = isset($_GET['level']) ? (string)$_GET['level'] : '';
          $className = isset($_GET['class_name']) ? (string)$_GET['class_name'] : '';
          $level = normalize_level($levelRaw);
          if (!$level || $className === '') {
            http_response_code(400);
            echo json_encode(['error' => 'Missing level or class_name']);
            return;
          }
          try {
            $st = $pdo->prepare("SELECT id FROM classes WHERE level = ? AND name = ? LIMIT 1");
            $st->execute([$level, $className]);
            $cls = $st->fetch(PDO::FETCH_ASSOC);
            if (!$cls) { echo json_encode(['success' => true, 'subjects' => []]); return; }
            $classId = (int)$cls['id'];

            $sql = "SELECT s.id AS subject_id, s.name AS name
                    FROM class_subjects cs
                    JOIN subjects s ON s.id = cs.subject_id
                    WHERE cs.class_id = ?
                    ORDER BY s.name";
            $q = $pdo->prepare($sql);
            $q->execute([$classId]);
            echo json_encode(['success' => true, 'subjects' => $q->fetchAll(PDO::FETCH_ASSOC)]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch class subjects: ' . $e->getMessage()]);
          }
          break;
        case 'student_quiz_history':
          // Auth: Students can fetch own; Admins can fetch any
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          $classId = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
          $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : 0;
          $userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
          if ($classId <= 0 || $subjectId <= 0) {
            http_response_code(400);
            echo json_encode(['error' => 'Missing class_id/subject_id']);
            return;
          }
          $isAdmin = (strtolower($requester['role'] ?? '') === 'admin');
          if (!$userId) { $userId = intval($requester['id']); }
          if (!$isAdmin && $userId !== intval($requester['id'])) {
            http_response_code(403);
            echo json_encode(['error' => 'Forbidden']);
            return;
          }
          try {
            $stmt = $pdo->prepare(
              "SELECT quiz_number AS number,
                      total_marks,
                      obtained_marks,
                      topic,
                      title,
                      scheduled_at,
                      attempted_at,
                      graded_at,
                      updated_at
               FROM student_quizzes
               WHERE class_id = ? AND subject_id = ? AND student_user_id = ?
               ORDER BY quiz_number DESC, updated_at DESC"
            );
            $stmt->execute([$classId, $subjectId, $userId]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'history' => $rows]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch quiz history: ' . $e->getMessage()]);
          }
          break;
        case 'student_assignment_history':
          // Auth: Students can fetch own; Admins can fetch any
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          $classId = isset($_GET['class_id']) ? intval($_GET['class_id']) : 0;
          $subjectId = isset($_GET['subject_id']) ? intval($_GET['subject_id']) : 0;
          $userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
          if ($classId <= 0 || $subjectId <= 0) {
            http_response_code(400);
            echo json_encode(['error' => 'Missing class_id/subject_id']);
            return;
          }
          $isAdmin = (strtolower($requester['role'] ?? '') === 'admin');
          if (!$userId) { $userId = intval($requester['id']); }
          if (!$isAdmin && $userId !== intval($requester['id'])) {
            http_response_code(403);
            echo json_encode(['error' => 'Forbidden']);
            return;
          }
          try {
            $stmt = $pdo->prepare(
              "SELECT assignment_number AS number,
                      total_marks,
                      obtained_marks,
                      title,
                      description,
                      deadline,
                      submitted_at,
                      graded_at,
                      updated_at
               FROM student_assignments
               WHERE class_id = ? AND subject_id = ? AND student_user_id = ?
               ORDER BY assignment_number DESC, updated_at DESC"
            );
            $stmt->execute([$classId, $subjectId, $userId]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            echo json_encode(['success' => true, 'history' => $rows]);
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch assignment history: ' . $e->getMessage()]);
          }
          break;
        case 'class_assessments':
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          listClassAssessments($pdo, $requester);
          break;
        case 'assignments':
          // Optional filters: level, class_name
          $level = isset($_GET['level']) ? normalize_level($_GET['level']) : null;
          $className = isset($_GET['class_name']) ? (string)$_GET['class_name'] : null;
          try {
            if ($level && $className) {
              $stmt = $pdo->prepare("SELECT c.id as class_id FROM classes c WHERE c.level = ? AND c.name = ? LIMIT 1");
              $stmt->execute([$level, $className]);
              $class = $stmt->fetch(PDO::FETCH_ASSOC);
              if (!$class) { echo json_encode(['success' => true, 'assignments' => []]); return; }
              $classId = (int)$class['class_id'];
              $sql = "SELECT a.id, a.teacher_user_id, u.name as teacher_name, a.subject_id, s.name as subject_name FROM teacher_class_subject_assignments a JOIN users u ON u.id = a.teacher_user_id JOIN subjects s ON s.id = a.subject_id WHERE a.class_id = ? ORDER BY s.name";
              $stmt = $pdo->prepare($sql);
              $stmt->execute([$classId]);
              echo json_encode(['success' => true, 'assignments' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
            } else {
              $sql = "SELECT a.id, a.teacher_user_id, u.name as teacher_name, a.class_id, c.name as class_name, c.level, a.subject_id, s.name as subject_name FROM teacher_class_subject_assignments a JOIN users u ON u.id = a.teacher_user_id JOIN classes c ON c.id = a.class_id JOIN subjects s ON s.id = a.subject_id ORDER BY c.level, c.name, s.name";
              $rows = $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
              echo json_encode(['success' => true, 'assignments' => $rows]);
            }
          } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to fetch assignments: ' . $e->getMessage()]);
          }
          break;
        case 'calendar':
            // Public read: monthly calendar (holidays + user events)
            $year = isset($_GET['year']) ? intval($_GET['year']) : null;
            $month = isset($_GET['month']) ? intval($_GET['month']) : null;
            if (!$year || !$month || $month < 1 || $month > 12) {
                http_response_code(400);
                echo json_encode(['error' => 'year and month are required']);
                return;
            }
            getCalendarMonthly($pdo, $year, $month);
            break;
        case 'term_start':
          // Get term start date (auth not strictly required to read)
          getTermStart($pdo);
          break;
        case 'notices':
          // Public list of notices with optional limit
          $limit = isset($_GET['limit']) ? intval($_GET['limit']) : 10;
          listNotices($pdo, $limit);
          break;
        case 'tickets':
          // Auth: Student sees own, Superadmin sees all
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          listTickets($pdo, $requester);
          break;
      case 'course_summary':
          // Fetch course summary/meta by (class_id, subject_id) or by names
          // Auth not strictly required to read
          getCourseSummary($pdo);
          break;
      case 'attendance_summary':
          // Auth: summary is for requester by default; Admin/Teacher can query any user_id
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          $userId = isset($_GET['user_id']) ? intval($_GET['user_id']) : intval($requester['id']);
          getAttendanceSummary($pdo, $requester, $userId);
          break;
      case 'student_marks':
          // Fetch marks for a class+subject and specific kind+number (public read allowed)
          getStudentMarks($pdo);
          break;
      case 'student_first_term_marks':
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getStudentTermMarks($pdo, $requester, 'first');
          break;
      case 'student_final_term_marks':
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getStudentTermMarks($pdo, $requester, 'final');
          break;
      case 'students_in_class':
          // List students by class name (best-effort via user_profiles.class)
          getStudentsInClass($pdo);
          break;
      case 'users':
        // ... existing
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        getAllUsers($pdo, $requester);
        break;
        case 'user':
            $id = isset($_GET['id']) ? $_GET['id'] : null;
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            getUserById($pdo, $id, $requester);
            break;
        case 'profile':
            $userId = isset($_GET['user_id']) ? $_GET['user_id'] : null;
            getUserProfile($pdo, $userId);
            break;
        case 'courses':
            getAllCourses($pdo);
            break;
        case 'my_courses':
          // Get courses assigned to the authenticated teacher
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getMyCourses($pdo, $requester);
          break;
        case 'my_student_courses':
          // Get enrolled courses (subjects) for the authenticated student
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getMyStudentCourses($pdo, $requester);
          break;
        case 'attendance':
          // Auth required to determine role-based data source
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          $userId = isset($_GET['user_id']) ? $_GET['user_id'] : null;
          getAttendance($pdo, $userId, $requester);
          break;
        case 'test':
            testConnection();
            break;
        case 'class_subject':
            // No GET handler for class_subject; use POST to add and DELETE to remove
            http_response_code(405);
            echo json_encode(['error' => 'Method not allowed']);
            break;
        case 'planner':
          global $JWT_SECRET;
          $requester = requireAuth($pdo, $JWT_SECRET);
          getPlannerData($pdo, $requester);
          break;
        default:
            http_response_code(404);
            echo json_encode(['error' => 'Endpoint not found']);
            break;
    }
}

/**
 * Save teacher-class-subject assignments
 * Input JSON: {
 *   teacher_user_id: number,
 *   level: string,            // e.g. "Early Years" | "Primary" | "Secondary"
 *   class_name: string,       // class name within level
 *   subjects: string[]        // subject names within level
 * }
 * Behavior:
 *   - Validates teacher exists and role is Admin (teacher) (any super admin check already done by caller)
 *   - Resolves class_id by (level, class_name)
 *   - Resolves subject_ids by (level, subject name)
 *   - For provided subject_ids:
 *       - Deletes any existing assignments for that class and those subjects (any teacher)
 *       - Inserts new rows assigning them to teacher_user_id
 *   - If subjects is empty, removes any assignments for (class_id, teacher_user_id)
 */
function saveAssignments($pdo, $input) {
    // Basic validation
    $teacherId = isset($input['teacher_user_id']) ? intval($input['teacher_user_id']) : 0;
    $levelRaw  = isset($input['level']) ? (string)$input['level'] : '';
    $className = isset($input['class_name']) ? (string)$input['class_name'] : '';
    $subjects  = isset($input['subjects']) && is_array($input['subjects']) ? $input['subjects'] : [];

    if ($teacherId <= 0 || $className === '') {
        http_response_code(400);
        echo json_encode(['error' => 'teacher_user_id and class_name are required']);
        return;
    }

    $level = normalize_level($levelRaw);
    if (!$level) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid or missing level']);
        return;
    }

    try {
        // Verify teacher
        $stmt = $pdo->prepare("SELECT id, role, is_super_admin FROM users WHERE id = ? LIMIT 1");
        $stmt->execute([$teacherId]);
        $teacher = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$teacher || $teacher['role'] !== 'Admin' || intval($teacher['is_super_admin']) !== 0) {
            http_response_code(400);
            echo json_encode(['error' => 'Invalid teacher_user_id']);
            return;
        }

        // Resolve class_id
        $stmt = $pdo->prepare("SELECT id FROM classes WHERE level = ? AND name = ? LIMIT 1");
        $stmt->execute([$level, $className]);
        $class = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$class) {
            http_response_code(400);
            echo json_encode(['error' => 'Class not found for given level and name']);
            return;
        }
        $classId = intval($class['id']);

        // Normalize subject names (trim)
        $subjects = array_values(array_filter(array_map(function($s){ return trim((string)$s); }, $subjects), function($s){ return $s !== ''; }));

        $pdo->beginTransaction();

        if (empty($subjects)) {
            // Clear any assignments for this teacher in this class
            $del = $pdo->prepare("DELETE FROM teacher_class_subject_assignments WHERE class_id = ? AND teacher_user_id = ?");
            $del->execute([$classId, $teacherId]);
            $pdo->commit();
            echo json_encode(['success' => true, 'updated' => 0, 'cleared' => true]);
            return;
        }

        // Resolve subject IDs for the provided names within the level
        // Build placeholders for IN clause
        $placeholders = implode(',', array_fill(0, count($subjects), '?'));
        $params = array_merge([$level], $subjects);
        $sql = "SELECT id, name FROM subjects WHERE level = ? AND name IN ($placeholders)";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $foundNames = array_map(function($r){ return $r['name']; }, $rows);
        $missing = array_values(array_diff($subjects, $foundNames));
        if (!empty($missing)) {
            $pdo->rollBack();
            http_response_code(400);
            echo json_encode(['error' => 'Unknown subjects for level', 'missing' => $missing]);
            return;
        }

        $subjectIds = array_map(function($r){ return intval($r['id']); }, $rows);

        // Delete any existing assignments for these subjects in this class (any teacher)
        $phDel = implode(',', array_fill(0, count($subjectIds), '?'));
        $delSql = "DELETE FROM teacher_class_subject_assignments WHERE class_id = ? AND subject_id IN ($phDel)";
        $delStmt = $pdo->prepare($delSql);
        $delStmt->execute(array_merge([$classId], $subjectIds));

        // Insert new assignments
        $ins = $pdo->prepare("INSERT INTO teacher_class_subject_assignments (teacher_user_id, class_id, subject_id, created_at) VALUES (?, ?, ?, NOW())");
        $inserted = 0;
        foreach ($subjectIds as $sid) {
            $ins->execute([$teacherId, $classId, $sid]);
            $inserted += $ins->rowCount();
        }

        $pdo->commit();
        echo json_encode(['success' => true, 'updated' => $inserted]);
    } catch (PDOException $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save assignments: ' . $e->getMessage()]);
    } catch (Exception $t) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        http_response_code(500);
        echo json_encode(['error' => 'Failed to save assignments: ' . $t->getMessage()]);
    }
}

/**
 * Handle POST requests
 */
function handlePostRequest($endpoint, $pdo) {
    // Robust POST body parsing: JSON first, then form-encoded fallback
    $raw = file_get_contents('php://input');
    $input = null;
    if ($raw !== false && strlen(trim($raw)) > 0) {
        $input = json_decode($raw, true);
        if (!is_array($input)) {
            $tmp = [];
            parse_str($raw, $tmp);
            if (is_array($tmp) && !empty($tmp)) {
                $input = $tmp;
            }
        }
    }
    if (!is_array($input)) {
        // As a last resort, use PHP's $_POST (for form-data)
        $input = $_POST ?? [];
    }
    
    switch ($endpoint) {
      case 'user_file_upload':
        // Auth required for uploads
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        // Ensure upload dir exists
        if (!is_dir(USER_FILES_UPLOAD_DIR)) {
            @mkdir(USER_FILES_UPLOAD_DIR, 0775, true);
        }

        // Validate file provided via multipart/form-data key 'file'
        if (!isset($_FILES['file']) || !is_array($_FILES['file'])) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'No file uploaded']);
            return;
        }

        $f = $_FILES['file'];
        $err = $f['error'] ?? UPLOAD_ERR_NO_FILE;
        if ($err !== UPLOAD_ERR_OK) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Upload error', 'code' => $err]);
            return;
        }

        $orig = basename($f['name']);
        $size = (int)$f['size'];
        $tmp  = $f['tmp_name'];
        $ext  = strtolower(pathinfo($orig, PATHINFO_EXTENSION));
        // Accept common doc/image types; adjust as needed
        $allowed = ['png','jpg','jpeg','gif','pdf','doc','docx','xls','xlsx','txt'];
        if ($ext && !in_array($ext, $allowed)) {
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Unsupported file type']);
            return;
        }

        $safeBase = 'uf_' . intval($requester['id']) . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3));
        $stored   = $safeBase . ($ext ? ('.' . $ext) : '');
        $destPath = rtrim(USER_FILES_UPLOAD_DIR, '/\\') . '/' . $stored;
        if (!@move_uploaded_file($tmp, $destPath)) {
            http_response_code(500);
            echo json_encode(['success' => false, 'error' => 'Failed to store file']);
            return;
        }

        $mime = function_exists('mime_content_type') ? @mime_content_type($destPath) : null;
        // Fallback: if mime detection fails (common on some setups), infer from extension
        if (!$mime || $mime === 'application/octet-stream') {
            switch ($ext) {
                case 'png':
                    $mime = 'image/png';
                    break;
                case 'jpg':
                case 'jpeg':
                    $mime = 'image/jpeg';
                    break;
                case 'gif':
                    $mime = 'image/gif';
                    break;
                case 'pdf':
                    $mime = 'application/pdf';
                    break;
                case 'doc':
                    $mime = 'application/msword';
                    break;
                case 'docx':
                    $mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
                    break;
                case 'xls':
                    $mime = 'application/vnd.ms-excel';
                    break;
                case 'xlsx':
                    $mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
                    break;
                case 'txt':
                    $mime = 'text/plain';
                    break;
                default:
                    // leave as-is
                    break;
            }
        }
        try {
            $stmt = $pdo->prepare("INSERT INTO user_files (user_id, user_name, original_file_name, stored_file_name, file_type, file_size, uploaded_at) VALUES (?, ?, ?, ?, ?, ?, NOW())");
            $stmt->execute([ intval($requester['id']), (string)$requester['name'], $orig, $stored, $mime, $size ]);
            echo json_encode(['success' => true, 'file_id' => $pdo->lastInsertId(), 'stored_file' => $stored, 'original_file' => $orig, 'mime' => $mime, 'size' => $size]);
        } catch (PDOException $e) {
            // Cleanup stored file if DB insert fails
            if (file_exists($destPath)) { @unlink($destPath); }
            http_response_code(500);
            echo json_encode(['success' => false, 'error' => 'DB error: ' . $e->getMessage()]);
        }
        break;
      case 'save_assignments':
        // Only Super Admin may change assignments
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        if (!($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 1)) {
          http_response_code(403);
          echo json_encode(['error' => 'Forbidden']);
          return;
        }
        saveAssignments($pdo, $input);
        break;
      case 'calendar_event':
        // Create user event (requires auth + role Teacher/Admin)
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        createCalendarEvent($pdo, $input, $requester);
        break;
      case 'create_challan':
        // Create a challan with optional file upload (multipart/form-data)
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        handleCreateChallan($pdo, $requester);
        break;
      case 'upload_payment_proof':
        // Student uploads payment proof
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        handleUploadPaymentProof($pdo, $requester);
        break;
      case 'challan_list':
        // List challans (Admin: all, Student: own)
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        listChallans($pdo, $requester);
        break;
        
      case 'challan_upload_proof':
        // Student uploads payment proof
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        handleUploadPaymentProof($pdo, $requester);
        break;
        
      case 'challan_verify':
        // Admin verifies/rejects challan
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        verifyChallan($pdo, $requester);
        break;
      case 'term_start':
         // Set/Update term start date (Admin or Super Admin only)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         setTermStart($pdo, $input, $requester);
         break;
      case 'course_summary':
         // Upsert course summary/meta (Admin Teacher only, NOT Super Admin)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         saveCourseSummary($pdo, $input, $requester);
         break;
      case 'attendance_record':
         // Upsert a daily attendance record (Admin/Teacher)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         upsertAttendanceRecord($pdo, $input, $requester);
         break;
      case 'student_marks_upsert':
         // Upsert marks for multiple students (Admin teacher only)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         upsertStudentMarks($pdo, $input, $requester);
         break;
      case 'student_first_term_marks_upsert':
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         upsertStudentTermMarks($pdo, $input, $requester, 'first');
         break;
      case 'student_final_term_marks_upsert':
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         upsertStudentTermMarks($pdo, $input, $requester, 'final');
         break;
      case 'auto_enroll_student':
         // Trigger (re)enrollment for a student based on their profile class/stream
         // Auth: Admin/Teacher for any user_id; Student can only enroll self
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         $targetUserId = isset($input['user_id']) ? (int)$input['user_id'] : (int)$requester['id'];
         if (($requester['role'] ?? '') !== 'Admin' && (int)$requester['id'] !== $targetUserId) {
             http_response_code(403);
             echo json_encode(['error' => 'Forbidden']);
             return;
         }
         try {
             $enrolled = autoEnrollStudent($pdo, $targetUserId);
             echo json_encode(['success' => true, 'enrolled' => $enrolled]);
         } catch (Exception $e) {
             http_response_code(500);
             echo json_encode(['error' => 'Auto-enroll failed: ' . $e->getMessage()]);
         }
         break;
      case 'record_class_attendance':
         // Record class attendance in batch (Teacher/Admin only, not SA)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         recordClassAttendance($pdo, $input, $requester);
         break;
      case 'notice':
         // Create a notice (Admin/Teacher/Principal)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         createNotice($pdo, $requester, $input);
         break;
      case 'ticket':
         // Create a ticket (Student or SA)
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         createTicket($pdo, $input, $requester);
         break;
      case 'planner_plan':
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        savePlannerPlan($pdo, $input, $requester);
        break;
      case 'planner_item':
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        savePlannerItem($pdo, $input, $requester);
        break;
      case 'class_assignment_save':
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        saveClassAssessment($pdo, $input, $requester, 'assignment');
        break;
      case 'class_quiz_save':
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        saveClassAssessment($pdo, $input, $requester, 'quiz');
        break;
      case 'planner_item_status':
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        updatePlannerItemStatus($pdo, $input ?? [], $requester);
        break;
      case 'upload_profile_picture':
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         handleUploadProfilePicture($pdo, $requester);
         break;
      case 'ticket_reply':
         // Reply to a ticket (Superadmin only) with fixed replies
         global $JWT_SECRET;
         $requester = requireAuth($pdo, $JWT_SECRET);
         replyTicket($pdo, $input, $requester);
         break;
      case 'class_subject':
        // Link a subject to a class (creates subject if missing) using class_subjects join table
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        if (($requester['role'] ?? '') !== 'Admin') {
          http_response_code(403);
          echo json_encode(['error' => 'Forbidden: Admin access required']);
          break;
        }
        $level = isset($input['level']) ? normalize_level((string)$input['level']) : null;
        $className = isset($input['class_name']) ? trim((string)$input['class_name']) : '';
        $subjectName = isset($input['subject_name']) ? trim((string)$input['subject_name']) : '';
        if (!$level || $className === '' || $subjectName === '') {
          http_response_code(400);
          echo json_encode(['error' => 'Missing level, class_name or subject_name']);
          break;
        }
        try {
          // Resolve class_id by level+name
          $cst = $pdo->prepare("SELECT id FROM classes WHERE level = ? AND name = ? LIMIT 1");
          $cst->execute([$level, $className]);
          $cls = $cst->fetch(PDO::FETCH_ASSOC);
          if (!$cls) { http_response_code(404); echo json_encode(['error' => 'Class not found']); break; }
          $classId = (int)$cls['id'];

          // Ensure subject exists within this level
          $sst = $pdo->prepare("SELECT id FROM subjects WHERE level = ? AND name = ? LIMIT 1");
          $sst->execute([$level, $subjectName]);
          $sub = $sst->fetch(PDO::FETCH_ASSOC);
          if ($sub) {
            $subjectId = (int)$sub['id'];
          } else {
            $ins = $pdo->prepare("INSERT INTO subjects (level, name, created_at) VALUES (?, ?, NOW())");
            $ins->execute([$level, $subjectName]);
            $subjectId = (int)$pdo->lastInsertId();
          }

          // Link subject to class idempotently
          $link = $pdo->prepare("INSERT IGNORE INTO class_subjects (class_id, subject_id) VALUES (?, ?)");
          $link->execute([$classId, $subjectId]);

          echo json_encode(['success' => true, 'message' => 'Linked', 'class_id' => $classId, 'subject_id' => $subjectId]);
        } catch (PDOException $e) {
          http_response_code(500);
          echo json_encode(['error' => 'Failed to link subject: ' . $e->getMessage()]);
        }
        break;
      case 'login':
        handleLogin($pdo, $input, isset($raw) ? $raw : null);
        break;
      case 'search_students':
        // Admins (teachers) and Super Admins only
        global $JWT_SECRET;
        $requester = requireAuth($pdo, $JWT_SECRET);
        if (!(($requester['role'] ?? '') === 'Admin')) {
          http_response_code(403);
          echo json_encode(['error' => 'Forbidden']);
          return;
        }
        searchStudents($pdo, $input);
        break;
        case 'register':
            handleRegister($pdo, $input);
            break;
        case 'create_user':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            createUserManaged($pdo, $input, $requester);
            break;
        case 'user':
            createUser($pdo, $input);
            break;
        case 'profile':
            createUserProfile($pdo, $input);
            break;
        case 'course':
            createCourse($pdo, $input);
            break;
        case 'attendance':
            global $requester;
            upsertAttendanceRecord($pdo, $input, $requester);
            break;
            
        case 'submit_assignment':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            submitAssignment($pdo, $input, $requester);
            break;
            
        case 'download_assignment':
            global $requester;
            downloadAssignment($pdo, $input, $requester);
            break;
            
        case 'get_assignment_submissions':
            global $requester;
            getAssignmentSubmissions($pdo, $input, $requester);
            break;
        case 'logout':
            handleLogout();
            break;
        case 'refresh_session':
            refreshUserSession($pdo, $input);
            break;
        case 'reset_password':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            resetPassword($pdo, $input, $requester);
            break;
        case 'user_profile_picture':
            // Get user's profile picture URL
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            $userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : (int)$requester['id'];
            
            // Only allow users to get their own picture or admins to get any picture
            // Use numeric comparison to avoid strict type mismatches (string vs int)
            if ((int)$userId !== (int)$requester['id'] && ($requester['role'] ?? '') !== 'Admin') {
                http_response_code(403);
                echo json_encode(['success' => false, 'error' => 'Forbidden']);
                return;
            }
            
            try {
                // Get the most recent image file for this user
                // Prefer rows with file_type like image/%, but also allow image extensions when MIME is missing
                $stmt = $pdo->prepare("
                    SELECT stored_file_name, file_type, uploaded_at 
                    FROM user_files 
                    WHERE user_id = ? 
                    AND (
                        (file_type IS NOT NULL AND file_type LIKE 'image/%')
                        OR LOWER(stored_file_name) LIKE '%.png'
                        OR LOWER(stored_file_name) LIKE '%.jpg'
                        OR LOWER(stored_file_name) LIKE '%.jpeg'
                        OR LOWER(stored_file_name) LIKE '%.gif'
                    )
                    ORDER BY uploaded_at DESC 
                    LIMIT 1
                ");
                $stmt->execute([$userId]);
                $file = $stmt->fetch(PDO::FETCH_ASSOC);
                
                if ($file) {
                    $baseUrl = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'];
                    // Use the API endpoint to serve the file instead of direct file access
                    $profilePictureUrl = $baseUrl . '/backend/api.php?endpoint=serve_file&file=' . urlencode($file['stored_file_name']);
                    echo json_encode([
                        'success' => true, 
                        'profile_picture_url' => $profilePictureUrl,
                        'file_info' => $file
                    ]);
                } else {
                    echo json_encode(['success' => false, 'error' => 'No profile picture found']);
                }
            } catch (PDOException $e) {
                http_response_code(500);
                echo json_encode(['success' => false, 'error' => 'Database error: ' . $e->getMessage()]);
            }
            break;
        case 'serve_file':
            // Serve uploaded files securely
            $fileName = isset($_GET['file']) ? $_GET['file'] : '';
            if (empty($fileName)) {
                http_response_code(400);
                echo json_encode(['error' => 'No file specified']);
                return;
            }
            
            // Validate file name to prevent directory traversal
            if (strpos($fileName, '..') !== false || strpos($fileName, '/') !== false || strpos($fileName, '\\') !== false) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid file name']);
                return;
            }
            
            $filePath = USER_FILES_UPLOAD_DIR . '/' . $fileName;
            if (!file_exists($filePath)) {
                // Fallback: try via DOCUMENT_ROOT mapping
                $docRoot = rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/\\');
                if (!empty($docRoot)) {
                    $altPath = $docRoot . '/backend/uploads/user_files/' . $fileName;
                    if (file_exists($altPath)) {
                        $filePath = $altPath;
                    }
                }
            }
            if (!file_exists($filePath)) {
                @error_log('[serve_file][POST] File not found at: ' . $filePath . ' | original=' . (USER_FILES_UPLOAD_DIR . '/' . $fileName));
                http_response_code(404);
                echo json_encode(['error' => 'File not found']);
                return;
            }
            
            // Set appropriate headers for image files
            $mimeType = mime_content_type($filePath);
            if (strpos($mimeType, 'image/') === 0) {
                header('Content-Type: ' . $mimeType);
                header('Content-Length: ' . filesize($filePath));
                header('Cache-Control: public, max-age=3600'); // Cache for 1 hour
                readfile($filePath);
            } else {
                http_response_code(400);
                echo json_encode(['error' => 'File type not supported']);
            }
            return; // Don't continue to default case
        case 'subject':
            // Add/create a subject for a given level (Super Admin)
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            
            // Check if user is super admin (has access to subject management)
            if (($requester['role'] ?? '') !== 'Admin') {
                http_response_code(403);
                echo json_encode(['error' => 'Forbidden: Admin access required']);
                return;
            }
            
            $level = isset($input['level']) ? trim((string)$input['level']) : '';
            $subjectName = isset($input['subject_name']) ? trim((string)$input['subject_name']) : '';
            
            if (!$level || !$subjectName) {
                http_response_code(400);
                echo json_encode(['error' => 'Missing level or subject_name']);
                return;
            }
            
            $normalizedLevel = normalize_level($level);
            if (!$normalizedLevel) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid level']);
                return;
            }
            
            try {
                // Check if subject already exists for this level
                $checkStmt = $pdo->prepare("SELECT id FROM subjects WHERE level = ? AND name = ?");
                $checkStmt->execute([$normalizedLevel, $subjectName]);
                $existing = $checkStmt->fetch(PDO::FETCH_ASSOC);
                
                if ($existing) {
                    // Subject already exists, just return success (re-attach scenario)
                    echo json_encode(['success' => true, 'message' => 'Subject already exists', 'subject_id' => $existing['id']]);
                } else {
                    // Create new subject
                    $insertStmt = $pdo->prepare("INSERT INTO subjects (level, name, created_at) VALUES (?, ?, NOW())");
                    $insertStmt->execute([$normalizedLevel, $subjectName]);
                    $subjectId = $pdo->lastInsertId();
                    echo json_encode(['success' => true, 'message' => 'Subject created successfully', 'subject_id' => $subjectId]);
                }
            } catch (PDOException $e) {
                http_response_code(500);
                echo json_encode(['error' => 'Failed to add subject: ' . $e->getMessage()]);
            }
            break;
        default:
            http_response_code(404);
            echo json_encode(['error' => 'Endpoint not found']);
            break;
    }
}

/**
 * Handle PUT requests
 */
function handlePutRequest($endpoint, $pdo) {
    $input = json_decode(file_get_contents('php://input'), true);
    
    switch ($endpoint) {
        case 'user':
            $id = isset($_GET['id']) ? $_GET['id'] : null;
            updateUser($pdo, $id, $input);
            break;
        case 'profile':
            $userId = isset($_GET['user_id']) ? $_GET['user_id'] : null;
            updateUserProfile($pdo, $userId, $input);
            break;
        case 'assessment_completion':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            upsertAssessmentCompletion($pdo, $input ?: [], $requester);
            break;
        default:
            http_response_code(404);
            echo json_encode(['error' => 'Endpoint not found']);
            break;
    }
}

/**
 * Handle DELETE requests
 */
function handleDeleteRequest($endpoint, $pdo) {
    // Handle endpoints with query parameters
    $baseEndpoint = explode('&', $endpoint)[0];
    
    switch ($baseEndpoint) {
        case 'user':
            $id = isset($_GET['id']) ? $_GET['id'] : null;
            deleteUser($pdo, $id);
            break;
        case 'planner_item':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            deletePlannerItem($pdo, $requester);
            break;
        case 'class_subject':
            // Unlink subject from a specific class (class_subjects join table)
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            if (($requester['role'] ?? '') !== 'Admin') {
                http_response_code(403);
                echo json_encode(['error' => 'Forbidden: Admin access required']);
                return;
            }
            $level = isset($_GET['level']) ? normalize_level((string)$_GET['level']) : null;
            $className = isset($_GET['class_name']) ? trim((string)$_GET['class_name']) : '';
            $subjectName = isset($_GET['subject_name']) ? trim((string)$_GET['subject_name']) : '';
            if (!$level || $className === '' || $subjectName === '') { http_response_code(400); echo json_encode(['error' => 'Missing level, class_name or subject_name']); return; }
            try {
                // Resolve class_id and subject_id
                $cst = $pdo->prepare("SELECT id FROM classes WHERE level = ? AND name = ? LIMIT 1");
                $cst->execute([$level, $className]);
                $cls = $cst->fetch(PDO::FETCH_ASSOC);
                if (!$cls) { http_response_code(404); echo json_encode(['error' => 'Class not found']); return; }
                $classId = (int)$cls['id'];

                $findStmt = $pdo->prepare("SELECT id FROM subjects WHERE level = ? AND name = ? LIMIT 1");
                $findStmt->execute([$level, $subjectName]);
                $subject = $findStmt->fetch(PDO::FETCH_ASSOC);
                if (!$subject) {
                    // Nothing to unlink; treat as success
                    echo json_encode(['success' => true, 'message' => 'Nothing to unlink']);
                    return;
                }
                $subjectId = (int)$subject['id'];

                $del = $pdo->prepare("DELETE FROM class_subjects WHERE class_id = ? AND subject_id = ?");
                $del->execute([$classId, $subjectId]);
                echo json_encode(['success' => true, 'message' => 'Subject unlinked from class']);
            } catch (PDOException $e) {
                http_response_code(500);
                echo json_encode(['error' => 'Failed to unlink subject: ' . $e->getMessage()]);
            }
            break;
        case 'assignment':
            global $JWT_SECRET;
            $requester = requireAuth($pdo, $JWT_SECRET);
            if (!($requester['role'] === 'Admin' && intval($requester['is_super_admin'] ?? 0) === 1)) {
                http_response_code(403);
                echo json_encode(['error' => 'Forbidden: Super Admin access required']);
                return;
            }
            $assignmentId = isset($_GET['id']) ? intval($_GET['id']) : 0;
            if ($assignmentId <= 0) {
                http_response_code(400);
                echo json_encode(['error' => 'Missing assignment id']);
                return;
            }
            try {
                $stmt = $pdo->prepare("DELETE FROM teacher_class_subject_assignments WHERE id = ?");
                $stmt->execute([$assignmentId]);
                if ($stmt->rowCount() === 0) {
                    http_response_code(404);
                    echo json_encode(['error' => 'Assignment not found']);
                    return;
                }
                echo json_encode(['success' => true, 'deleted' => true]);
            } catch (PDOException $e) {
                http_response_code(500);
                echo json_encode(['error' => 'Failed to delete assignment: ' . $e->getMessage()]);
            }
            break;
        default:
            http_response_code(404);
            echo json_encode(['error' => 'Endpoint not found']);
            break;
    }
}

/**
 * User Authentication Functions
 */
function handleLogin($pdo, $input, $rawBody = null) {
    if (!isset($input['email']) || !isset($input['password'])) {
        http_response_code(400);
        echo json_encode([
            'error' => 'Email and password are required',
            'debug' => [
                'raw_len' => is_string($rawBody) ? strlen($rawBody) : null,
                'raw_preview' => is_string($rawBody) ? substr($rawBody, 0, 120) : null,
                'input_keys' => is_array($input) ? array_keys($input) : null,
                'content_type' => $_SERVER['CONTENT_TYPE'] ?? ($_SERVER['HTTP_CONTENT_TYPE'] ?? null),
                'post_count' => isset($_POST) ? count($_POST) : null,
            ]
        ]);
        return;
    }
    
    $email = $input['email'];
    $password = $input['password'];
    
    try {
        $stmt = $pdo->prepare("SELECT id, name, email, password FROM users WHERE email = ?");
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($user) {
            // Debug: Check if password verification works
            $passwordValid = password_verify($password, $user['password']);
            
            if ($passwordValid) {
                // Remove password from response
                unset($user['password']);
                // Compute role from role tables
                $r = compute_role($pdo, $user['id']);
                $user['role'] = $r['role'];
                $user['is_super_admin'] = $r['is_super_admin'];
                // Issue JWT token (1 hour expiry)
                global $JWT_SECRET;
                $claims = [
                    'sub' => $user['id'],
                    'role' => $user['role'],
                    'is_super_admin' => (int)$user['is_super_admin'],
                    'exp' => time() + 3600
                ];
                $token = jwt_encode($claims, $JWT_SECRET);
                echo json_encode([
                    'success' => true,
                    'message' => 'Login successful',
                    'token' => $token,
                    'user' => $user
                ]);
            } else {
                http_response_code(401);
                echo json_encode([
                    'error' => 'Invalid email or password',
                    'debug' => [
                        'email_provided' => $email,
                        'user_found' => true,
                        'password_verification' => false,
                        'password_hash_length' => strlen($user['password'])
                    ]
                ]);
            }
        } else {
            http_response_code(401);
            echo json_encode([
                'error' => 'Invalid email or password',
                'debug' => [
                    'email_provided' => $email,
                    'user_found' => false
                ]
            ]);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Login failed: ' . $e->getMessage()]);
    }
}

function handleRegister($pdo, $input) {
    if (!isset($input['name']) || !isset($input['email']) || !isset($input['password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Name, email, and password are required']);
        return;
    }
    
    $name = $input['name'];
    $email = $input['email'];
    $password = password_hash($input['password'], PASSWORD_DEFAULT);
    $roleInput = isset($input['role']) ? $input['role'] : 'Student';
    list($dbRole, $mappedSA) = map_role_and_super($roleInput);
    // Public register cannot create Super Admins
    $mappedSA = 0;
    
    try {
        // Check if user already exists
        $stmt = $pdo->prepare("SELECT id FROM users WHERE email = ?");
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            http_response_code(409);
            echo json_encode(['error' => 'User with this email already exists']);
            return;
        }
        
        // Create new user (public registration never sets is_super_admin)
        $stmt = $pdo->prepare("INSERT INTO users (name, email, password, role, is_super_admin, created_at) VALUES (?, ?, ?, ?, ?, NOW())");
        $stmt->execute([$name, $email, $password, $dbRole, $mappedSA]);
        
        $userId = $pdo->lastInsertId();
        
        echo json_encode([
            'success' => true,
            'message' => 'User registered successfully',
            'user_id' => $userId
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Registration failed: ' . $e->getMessage()]);
    }
}

/**
 * User Management Functions
 */
function getAllUsers($pdo, $requester) {
    try {
        // Super Admin sees all Users; Teacher sees Students; Student sees self only
        if ($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 1) {
            $stmt = $pdo->query("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC");
            $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
        } elseif ($requester['role'] === 'Admin') {
            $stmt = $pdo->prepare("SELECT u.id, u.name, u.email, u.created_at
                                   FROM users u JOIN students s ON s.user_id = u.id
                                   ORDER BY u.created_at DESC");
            $stmt->execute();
            $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
        } else {
            $stmt = $pdo->prepare("SELECT id, name, email, created_at FROM users WHERE id = ?");
            $stmt->execute([$requester['id']]);
            $users = $stmt->fetchAll(PDO::FETCH_ASSOC);
        }

        // Attach computed role info to each user for compatibility
        foreach ($users as &$u) {
            $r = compute_role($pdo, $u['id']);
            $u['role'] = $r['role'];
            $u['is_super_admin'] = $r['is_super_admin'];
        }
        echo json_encode(['success' => true, 'users' => $users]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch users: ' . $e->getMessage()]);
    }
}

function getUserById($pdo, $id, $requester) {
    if (!$id) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    try {
        $stmt = $pdo->prepare("SELECT id, name, email, created_at FROM users WHERE id = ?");
        $stmt->execute([$id]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($user) {
            // Compute target role
            $r = compute_role($pdo, $user['id']);
            $user['role'] = $r['role'];
            $user['is_super_admin'] = $r['is_super_admin'];
            // Authorization: Teacher can only view Students; Student can only view self
            if ($requester['role'] === 'Admin') {
                if ((int)$requester['is_super_admin'] !== 1 && $user['role'] !== 'Student') {
                    http_response_code(403);
                    echo json_encode(['error' => 'Forbidden']);
                    return;
                }
            } elseif ($requester['id'] != $user['id']) {
                http_response_code(403);
                echo json_encode(['error' => 'Forbidden']);
                return;
            }
            echo json_encode(['success' => true, 'user' => $user]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch user: ' . $e->getMessage()]);
    }
}

// Managed user creation with role enforcement (requires auth)
function createUserManaged($pdo, $input, $requester) {
    if (!isset($input['name']) || !isset($input['email']) || !isset($input['password']) || !isset($input['role'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Name, email, password, and role are required']);
        return;
    }

    $name = $input['name'];
    $email = $input['email'];
    $password = password_hash($input['password'], PASSWORD_DEFAULT);
    $roleInput = $input['role'];
    list($role, $mappedSA) = map_role_and_super($roleInput);
    $is_super_admin = isset($input['is_super_admin']) ? (int)$input['is_super_admin'] : $mappedSA;

    // Authorization rules
    $requesterIsSA = ($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 1);
    $requesterIsTeacher = ($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 0);

    if ($requesterIsTeacher) {
        if ($role !== 'Student') {
            http_response_code(403);
            echo json_encode(['error' => 'Teachers can only create Students']);
            return;
        }
        $is_super_admin = 0; // teacher cannot set SA
    }
    if (!$requesterIsSA && !$requesterIsTeacher) {
        http_response_code(403);
        echo json_encode(['error' => 'Forbidden']);
        return;
    }

    try {
        $stmt = $pdo->prepare("SELECT id FROM users WHERE email = ?");
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            http_response_code(409);
            echo json_encode(['error' => 'User with this email already exists']);
            return;
        }
        $stmt = $pdo->prepare("INSERT INTO users (name, email, password, role, is_super_admin, created_at) VALUES (?, ?, ?, ?, ?, NOW())");
        $stmt->execute([$name, $email, $password, $role, $is_super_admin]);
        $userId = (int)$pdo->lastInsertId();

        // Maintain role mapping tables
        try {
            if ($role === 'Admin') {
                if ((int)$is_super_admin === 1) {
                    // Super Admin entry
                    $adm = $pdo->prepare("INSERT INTO admins (user_id, is_super_admin) VALUES (?, 1) ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin)");
                    $adm->execute([$userId]);
                } else {
                    // Teacher entry (non-super admin)
                    $tch = $pdo->prepare("INSERT IGNORE INTO teachers (user_id) VALUES (?)");
                    $tch->execute([$userId]);
                }
            } else if ($role === 'Student') {
                $stu = $pdo->prepare("INSERT IGNORE INTO students (user_id) VALUES (?)");
                $stu->execute([$userId]);
            }
        } catch (Exception $ign) { /* best-effort mapping */ }

        echo json_encode(['success' => true, 'message' => 'User created successfully', 'user_id' => $userId]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create user: ' . $e->getMessage()]);
    }
}

function resetPassword($pdo, $input, $requester) {
    if (!isset($input['user_id']) || !isset($input['new_password'])) {
        http_response_code(400);
        echo json_encode(['error' => 'user_id and new_password are required']);
        return;
    }
    $targetId = (int)$input['user_id'];
    $newHash = password_hash($input['new_password'], PASSWORD_DEFAULT);

    try {
        $stmt = $pdo->prepare("SELECT id, role, is_super_admin FROM users WHERE id = ?");
        $stmt->execute([$targetId]);
        $target = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$target) {
            http_response_code(404);
            echo json_encode(['error' => 'Target user not found']);
            return;
        }

        $requesterIsSA = ($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 1);
        $requesterIsTeacher = ($requester['role'] === 'Admin' && (int)$requester['is_super_admin'] === 0);

        // Permissions: SA can reset any; Teacher only Students; Student only self
        $allowed = false;
        if ($requesterIsSA) {
            $allowed = true;
        } elseif ($requesterIsTeacher && $target['role'] === 'Student') {
            $allowed = true;
        } elseif ($requester['id'] == $target['id']) {
            $allowed = true;
        }
        if (!$allowed) {
            http_response_code(403);
            echo json_encode(['error' => 'Forbidden']);
            return;
        }

        $stmt = $pdo->prepare("UPDATE users SET password = ?, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$newHash, $targetId]);
        echo json_encode(['success' => true, 'message' => 'Password reset successfully']);
    } catch (PDOException $e) {
        echo json_encode(['error' => 'Failed to reset password: ' . $e->getMessage()]);
    }
}

function createUser($pdo, $input) {
    if (!isset($input['name']) || !isset($input['email'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Name and email are required']);
        return;
    }
    
    $name = $input['name'];
    $email = $input['email'];
    $roleInput = isset($input['role']) ? $input['role'] : 'Student';
    list($dbRole, $mappedSA) = map_role_and_super($roleInput);
    // Public create endpoint cannot create Super Admins
    $mappedSA = 0;
    $password = isset($input['password']) ? password_hash($input['password'], PASSWORD_DEFAULT) : null;
    
    try {
        // Check if user already exists
        $stmt = $pdo->prepare("SELECT id FROM users WHERE email = ?");
        $stmt->execute([$email]);
        if ($stmt->fetch()) {
            http_response_code(409);
            echo json_encode(['error' => 'User with this email already exists']);
            return;
        }
        
        if ($password) {
            $stmt = $pdo->prepare("INSERT INTO users (name, email, password, role, is_super_admin, created_at) VALUES (?, ?, ?, ?, ?, NOW())");
            $stmt->execute([$name, $email, $password, $dbRole, $mappedSA]);
        } else {
            $stmt = $pdo->prepare("INSERT INTO users (name, email, role, is_super_admin, created_at) VALUES (?, ?, ?, ?, NOW())");
            $stmt->execute([$name, $email, $dbRole, $mappedSA]);
        }

        $userId = (int)$pdo->lastInsertId();

        // Maintain role mapping tables for public create as well
        try {
            if ($dbRole === 'Admin') {
                if ((int)$mappedSA === 1) {
                    $adm = $pdo->prepare("INSERT INTO admins (user_id, is_super_admin) VALUES (?, 1) ON DUPLICATE KEY UPDATE is_super_admin = VALUES(is_super_admin)");
                    $adm->execute([$userId]);
                } else {
                    $tch = $pdo->prepare("INSERT IGNORE INTO teachers (user_id) VALUES (?)");
                    $tch->execute([$userId]);
                }
            } else if ($dbRole === 'Student') {
                $stu = $pdo->prepare("INSERT IGNORE INTO students (user_id) VALUES (?)");
                $stu->execute([$userId]);
            }
        } catch (Exception $ign) { /* best-effort mapping */ }

        echo json_encode([
            'success' => true,
            'message' => 'User created successfully',
            'user_id' => $userId
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create user: ' . $e->getMessage()]);
    }
}

function updateUser($pdo, $id, $input) {
    if (!$id) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    $updates = [];
    $params = [];
    
    if (isset($input['name'])) {
        $updates[] = "name = ?";
        $params[] = $input['name'];
    }
    if (isset($input['email'])) {
        $updates[] = "email = ?";
        $params[] = $input['email'];
    }
    if (isset($input['role'])) {
        // Map UI role into DB role and SA flag
        list($mappedRole, $mappedSA) = map_role_and_super($input['role']);
        $updates[] = "role = ?";
        $params[] = $mappedRole;
        $updates[] = "is_super_admin = ?";
        $params[] = (int)$mappedSA;
    }
    
    if (empty($updates)) {
        http_response_code(400);
        echo json_encode(['error' => 'No fields to update']);
        return;
    }
    
    $params[] = $id;
    $sql = "UPDATE users SET " . implode(", ", $updates) . " WHERE id = ?";
    
    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        
        if ($stmt->rowCount() > 0) {
            echo json_encode(['success' => true, 'message' => 'User updated successfully']);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update user: ' . $e->getMessage()]);
    }
}

function deleteUser($pdo, $id) {
    if (!$id) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    try {
        $stmt = $pdo->prepare("DELETE FROM users WHERE id = ?");
        $stmt->execute([$id]);
        
        if ($stmt->rowCount() > 0) {
            echo json_encode(['success' => true, 'message' => 'User deleted successfully']);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to delete user: ' . $e->getMessage()]);
    }
}

/**
 * User Profile Functions
 */
function getUserProfile($pdo, $userId) {
    if (!$userId) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    try {
        $stmt = $pdo->prepare("SELECT * FROM user_profiles WHERE user_id = ?");
        $stmt->execute([$userId]);
        $profile = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($profile) {
            echo json_encode(['success' => true, 'profile' => $profile]);
        } else {
            echo json_encode(['success' => true, 'profile' => null]);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch profile: ' . $e->getMessage()]);
    }
}

function createUserProfile($pdo, $input) {
    if (!isset($input['user_id'])) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    $userId = $input['user_id'];
    
    try {
        // Check if profile already exists
        $stmt = $pdo->prepare("SELECT id FROM user_profiles WHERE user_id = ?");
        $stmt->execute([$userId]);
        if ($stmt->fetch()) {
            http_response_code(409);
            echo json_encode(['error' => 'Profile already exists for this user']);
            return;
        }
        
        // Create profile with available fields
        $fields = ['user_id', 'full_name', 'cnic', 'date_of_birth', 'gender', 'blood_group', 
                   'nationality', 'religion', 'roll_number', 'class', 'batch', 'enrollment_date',
                   'phone', 'whatsapp', 'alternative_phone', 'emergency_contact', 'emergency_relationship',
                   'alternative_emergency', 'alternative_emergency_relationship', 'current_address',
                   'permanent_address', 'city', 'province', 'postal_code',
                   'registration_no', 'class_teacher_of'];
        
        $profileFields = [];
        $placeholders = [];
        $values = [];
        
        foreach ($fields as $field) {
            if (isset($input[$field])) {
                $profileFields[] = $field;
                $placeholders[] = "?";
                $values[] = $input[$field];
            }
        }
        
        if (empty($profileFields)) {
            http_response_code(400);
            echo json_encode(['error' => 'No profile data provided']);
            return;
        }
        
        $sql = "INSERT INTO user_profiles (" . implode(", ", $profileFields) . ") VALUES (" . implode(", ", $placeholders) . ")";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($values);
        
        $profileId = $pdo->lastInsertId();
        
        // Attempt auto-enrollment if this is a Student and class/batch provided
        try {
            if (isset($input['class'])) {
                // Check if user is a student
                $chk = $pdo->prepare("SELECT 1 FROM students WHERE user_id = ? LIMIT 1");
                $chk->execute([$userId]);
                if ($chk->fetch()) {
                    autoEnrollStudent($pdo, (int)$userId);
                }
            }
        } catch (Exception $e) {
            // best-effort; do not fail profile creation
        }

        echo json_encode([
            'success' => true,
            'message' => 'Profile created successfully',
            'profile_id' => $profileId
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create profile: ' . $e->getMessage()]);
    }
}

function updateUserProfile($pdo, $userId, $input) {
    if (!$userId) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    $updates = [];
    $params = [];
    
    $fields = ['full_name', 'cnic', 'date_of_birth', 'gender', 'blood_group', 
               'nationality', 'religion', 'roll_number', 'class', 'batch', 'enrollment_date',
               'phone', 'whatsapp', 'alternative_phone', 'emergency_contact', 'emergency_relationship',
               'alternative_emergency', 'alternative_emergency_relationship', 'current_address',
               'permanent_address', 'city', 'province', 'postal_code',
               'registration_no', 'class_teacher_of'];
    
    foreach ($fields as $field) {
        if (isset($input[$field])) {
            $updates[] = "$field = ?";
            $params[] = $input[$field];
        }
    }
    
    if (empty($updates)) {
        http_response_code(400);
        echo json_encode(['error' => 'No fields to update']);
        return;
    }
    
    // If caller is attempting to set class_teacher_of, enforce uniqueness.
    $wantsClassTeacher = array_key_exists('class_teacher_of', $input);
    $newClassTeacher = isset($input['class_teacher_of']) ? trim((string)$input['class_teacher_of']) : null;
    $allowReplace = isset($input['replace_class_teacher']) && (int)$input['replace_class_teacher'] === 1;

    $params[] = $userId;
    $sql = "UPDATE user_profiles SET " . implode(", ", $updates) . " WHERE user_id = ?";
    
    try {
        if ($wantsClassTeacher && $newClassTeacher !== null && $newClassTeacher !== '') {
            // Check if another user already holds this class as class teacher
            $chk = $pdo->prepare("SELECT user_id FROM user_profiles WHERE class_teacher_of = ? AND user_id <> ? LIMIT 1");
            $chk->execute([$newClassTeacher, $userId]);
            $row = $chk->fetch(PDO::FETCH_ASSOC);
            if ($row && isset($row['user_id'])) {
                if ($allowReplace) {
                    // Replace: clear previous teacher, then apply update in a transaction
                    $pdo->beginTransaction();
                    try {
                        $clr = $pdo->prepare("UPDATE user_profiles SET class_teacher_of = NULL WHERE class_teacher_of = ?");
                        $clr->execute([$newClassTeacher]);
                        $stmt = $pdo->prepare($sql);
                        $stmt->execute($params);
                        $pdo->commit();
                    } catch (Exception $ex) {
                        $pdo->rollBack();
                        throw $ex;
                    }
                } else {
                    http_response_code(409);
                    echo json_encode(['error' => 'Class already has a class teacher assigned']);
                    return;
                }
            } else {
                // No conflict; proceed normally
                $stmt = $pdo->prepare($sql);
                $stmt->execute($params);
            }
        } else {
            // Not setting class_teacher_of or clearing it; proceed normally
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
        }
        
        if ($stmt->rowCount() > 0) {
            // After update, if class or batch changed, (re)enroll student
            try {
                if (isset($input['class']) || isset($input['batch'])) {
                    $chk = $pdo->prepare("SELECT 1 FROM students WHERE user_id = ? LIMIT 1");
                    $chk->execute([$userId]);
                    if ($chk->fetch()) {
                        autoEnrollStudent($pdo, (int)$userId);
                    }
                }
            } catch (Exception $e) {
                // ignore
            }
            echo json_encode(['success' => true, 'message' => 'Profile updated successfully']);
        } else {
            // Try to create profile if it doesn't exist
            createUserProfile($pdo, array_merge($input, ['user_id' => $userId]));
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to update profile: ' . $e->getMessage()]);
    }
}

/**
 * Course Management Functions
 */
function getAllCourses($pdo) {
    try {
        $stmt = $pdo->query("SELECT * FROM courses ORDER BY name");
        $courses = $stmt->fetchAll(PDO::FETCH_ASSOC);
        echo json_encode(['success' => true, 'courses' => $courses]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch courses: ' . $e->getMessage()]);
    }
}

function createCourse($pdo, $input) {
    if (!isset($input['name'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Course name is required']);
        return;
    }
    
    $name = $input['name'];
    $description = isset($input['description']) ? $input['description'] : '';
    
    try {
        $stmt = $pdo->prepare("INSERT INTO courses (name, description, created_at) VALUES (?, ?, NOW())");
        $stmt->execute([$name, $description]);
        
        $courseId = $pdo->lastInsertId();
        
        echo json_encode([
            'success' => true,
            'message' => 'Course created successfully',
            'course_id' => $courseId
        ]);
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to create course: ' . $e->getMessage()]);
    }
}

/**
 * Attendance Functions
 */
function getAttendance($pdo, $userId, $requester) {
    // Ensure clean JSON output: clear ALL existing buffers and set JSON header once
    while (function_exists('ob_get_level') && ob_get_level() > 0) { @ob_end_clean(); }
    header('Content-Type: application/json; charset=UTF-8');

    if (!$userId) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'User ID is required']);
        return;
    }

    try {
        // Branch source by role: Admin -> attendance_records, Student -> class_attendance
        $role = strtolower($requester['role'] ?? '');
        if ($role === 'admin') {
            // Admin view: simple per-user daily records
            $stmt = $pdo->prepare("SELECT `date`, `status` FROM attendance_records WHERE user_id = ? ORDER BY `date` DESC");
            $stmt->execute([$userId]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            // Normalize keys for UI compatibility
            $attendance = array_map(function($r){
                return ['date' => $r['date'], 'status' => strtolower($r['status'] ?? ''), 'class_name' => null];
            }, $rows);
        } else {
            // Student view: class_attendance
            $className = isset($_GET['class_name']) ? trim((string)$_GET['class_name']) : '';
            if ($className !== '') {
                $stmt = $pdo->prepare("SELECT attendance_date AS `date`, `status`, `class_name`
                                       FROM class_attendance
                                       WHERE student_user_id = ? AND class_name = ?
                                       ORDER BY attendance_date DESC");
                $stmt->execute([$userId, $className]);
            } else {
                $stmt = $pdo->prepare("SELECT attendance_date AS `date`, `status`, `class_name`
                                       FROM class_attendance
                                       WHERE student_user_id = ?
                                       ORDER BY attendance_date DESC");
                $stmt->execute([$userId]);
            }
            $attendance = $stmt->fetchAll(PDO::FETCH_ASSOC);
        }
        echo json_encode(['success' => true, 'attendance' => $attendance]);
        // Terminate immediately to avoid any accidental extra output
        exit();
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Failed to fetch attendance: ' . $e->getMessage()]);
        exit();
    }
}

/**
 * Additional functions needed by Flutter app
 */

// Function to handle logout
function handleLogout() {
    echo json_encode([
        'success' => true,
        'message' => 'Logout successful'
    ]);
}

// Function to test connection
function testConnection() {
    echo json_encode([
        'success' => true,
        'message' => 'Connection test successful',
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

// Submit assignment (file or link)
function submitAssignment($pdo, $input, $requester) {
    // Verify required fields
    $required = ['class_id', 'subject_id', 'assignment_number', 'submission_type'];
    foreach ($required as $field) {
        if (!isset($input[$field])) {
            http_response_code(400);
            echo json_encode(['error' => "Missing required field: $field"]);
            return;
        }
    }

    $classId = (int)$input['class_id'];
    $subjectId = (int)$input['subject_id'];
    $assignmentNumber = (int)$input['assignment_number'];
    $submissionType = $input['submission_type'];
    $studentId = (int)$requester['id'];

    // Validate submission type
    if (!in_array($submissionType, ['link', 'file'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid submission_type. Must be "link" or "file"']);
        return;
    }

    // Handle file upload
    if ($submissionType === 'file') {
        if (empty($_FILES['file'])) {
            http_response_code(400);
            echo json_encode(['error' => 'No file uploaded']);
            return;
        }

        $file = $_FILES['file'];
        $originalName = basename($file['name']);
        $fileType = $file['type'];
        $fileSize = $file['size'];
        
        // Create uploads directory if it doesn't exist (uses absolute path constant)
        $uploadsDir = defined('ASSIGNMENTS_UPLOAD_DIR') ? ASSIGNMENTS_UPLOAD_DIR : (__DIR__ . '/uploads/assignments');
        if (!is_dir($uploadsDir)) {
            @mkdir($uploadsDir, 0755, true);
        }
        
        // Use original filename with timestamp to avoid conflicts
        $timestamp = time();
        $extension = pathinfo($originalName, PATHINFO_EXTENSION);
        $baseName = pathinfo($originalName, PATHINFO_FILENAME);
        $serverFileName = "{$baseName}_{$timestamp}.{$extension}";
        $filePath = rtrim($uploadsDir, '/\\') . '/' . $serverFileName;
        
        // Move uploaded file to permanent location
        if (!move_uploaded_file($file['tmp_name'], $filePath)) {
            http_response_code(500);
            echo json_encode(['error' => 'Failed to save uploaded file']);
            return;
        }
        // Persist the actual stored file name
        $fileName = $serverFileName;
    } else {
        // Handle link submission
        if (empty($input['content'])) {
            http_response_code(400);
            echo json_encode(['error' => 'No content provided for link submission']);
            return;
        }
        $fileName = $input['content']; // Store URL in file_name for links
        $fileType = null;
        $fileSize = null;
    }

    try {
        // Check for existing submission
        $stmt = $pdo->prepare(
            "SELECT id FROM assignment_submissions 
            WHERE student_id = ? AND class_id = ? AND subject_id = ? AND assignment_number = ?"
        );
        $stmt->execute([$studentId, $classId, $subjectId, $assignmentNumber]);
        $existing = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($existing) {
            // Delete old file if updating with new file
            if ($submissionType === 'file') {
                $oldStmt = $pdo->prepare("SELECT file_name FROM assignment_submissions WHERE id = ?");
                $oldStmt->execute([$existing['id']]);
                $oldFile = $oldStmt->fetch(PDO::FETCH_ASSOC);
                if ($oldFile && $oldFile['file_name']) {
                    $oldBaseDir = defined('ASSIGNMENTS_UPLOAD_DIR') ? ASSIGNMENTS_UPLOAD_DIR : (__DIR__ . '/uploads/assignments');
                    $oldFilePath = rtrim($oldBaseDir, '/\\') . '/' . basename($oldFile['file_name']);
                    if (file_exists($oldFilePath)) {
                        unlink($oldFilePath);
                    }
                }
            }
            
            // Update existing submission
            $stmt = $pdo->prepare(
                "UPDATE assignment_submissions 
                SET submission_type = ?, file_name = ?, file_type = ?, file_size = ?, 
                    updated_at = NOW() 
                WHERE id = ?"
            );
            $params = [
                $submissionType,
                $fileName,
                $fileType,
                $fileSize,
                $existing['id']
            ];
        } else {
            // Create new submission
            $stmt = $pdo->prepare(
                "INSERT INTO assignment_submissions 
                (student_id, class_id, subject_id, assignment_number, submission_type, 
                 file_name, file_type, file_size, status, submitted_at) 
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'submitted', NOW())"
            );
            $params = [
                $studentId,
                $classId,
                $subjectId,
                $assignmentNumber,
                $submissionType,
                $fileName,
                $fileType,
                $fileSize
            ];
        }

        $stmt->execute($params);
        $submissionId = $existing ? $existing['id'] : $pdo->lastInsertId();

        echo json_encode([
            'success' => true,
            'submission_id' => $submissionId,
            'message' => 'Assignment submitted successfully'
        ]);

    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Database error: ' . $e->getMessage()]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Error processing submission: ' . $e->getMessage()]);
    }
}

// Download assignment file
function downloadAssignment($pdo, $input, $requester) {
    if (!isset($input['submission_id'])) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing submission_id']);
        return;
    }

    $submissionId = (int)$input['submission_id'];
    $userId = (int)$requester['id'];
    $userRole = $requester['role'];

    try {
        // Get submission details
        $stmt = $pdo->prepare(
            "SELECT s.*, u.name as student_name, c.name as class_name, sub.name as subject_name
            FROM assignment_submissions s
            JOIN users u ON u.id = s.student_id
            JOIN classes c ON c.id = s.class_id
            JOIN subjects sub ON sub.id = s.subject_id
            WHERE s.id = ?"
        );
        $stmt->execute([$submissionId]);
        $submission = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$submission) {
            http_response_code(404);
            echo json_encode(['error' => 'Submission not found']);
            return;
        }

        // Check permissions - admin can download all files
        if ($userRole !== 'admin' && $userRole !== 'teacher') {
            if ($userRole !== 'student' || $userId !== (int)$submission['student_id']) {
                http_response_code(403);
                echo json_encode(['error' => 'Permission denied']);
                return;
            }
        }

        // Handle link submissions
        if ($submission['submission_type'] === 'link') {
            echo json_encode([
                'success' => true,
                'type' => 'link',
                'url' => $submission['file_name']
            ]);
            return;
        }

        // Handle file submissions
        $baseDir = defined('ASSIGNMENTS_UPLOAD_DIR') ? ASSIGNMENTS_UPLOAD_DIR : (__DIR__ . '/uploads/assignments');
        $filePath = rtrim($baseDir, '/\\') . '/' . basename($submission['file_name']);
        if (!file_exists($filePath)) {
            // Fallback: try timestamped variant if DB has original name
            $orig = basename($submission['file_name']);
            $ext = pathinfo($orig, PATHINFO_EXTENSION);
            $base = pathinfo($orig, PATHINFO_FILENAME);
            $pattern = rtrim($baseDir, '/\\') . '/' . $base . '_*' . ($ext ? ('.' . $ext) : '');
            $matches = glob($pattern);
            if ($matches && count($matches) > 0) {
                usort($matches, function($a, $b){ return filemtime($b) <=> filemtime($a); });
                $filePath = $matches[0];
            } else {
                http_response_code(404);
                echo json_encode(['error' => 'File not found on server']);
                return;
            }
        }

        // Set headers for file download
        header('Content-Type: ' . ($submission['file_type'] ?: 'application/octet-stream'));
        header('Content-Disposition: attachment; filename="' . basename($submission['file_name']) . '"');
        header('Content-Length: ' . filesize($filePath));
        
        // Output file
        readfile($filePath);
        exit;

    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to download assignment: ' . $e->getMessage()]);
    }
}

// Get assignment submissions for admin/teacher view
function getAssignmentSubmissions($pdo, $input, $requester) {
    $userId = (int)$requester['id'];
    $userRole = $requester['role'];

    $where = "WHERE 1=1";
    $params = [];

    if ($userRole === 'student') {
        $where .= " AND s.student_id = ?";
        $params[] = $userId;
    }
    // Admin and teachers can see all submissions

    // Add optional filters
    if (isset($input['class_id']) && $input['class_id']) {
        $where .= " AND s.class_id = ?";
        $params[] = (int)$input['class_id'];
    }
    if (isset($input['subject_id']) && $input['subject_id']) {
        $where .= " AND s.subject_id = ?";
        $params[] = (int)$input['subject_id'];
    }

    try {
        $stmt = $pdo->prepare(
            "SELECT s.id, s.student_id, s.class_id, s.subject_id, s.assignment_number,
                    s.submission_type, s.file_name, s.file_type, s.file_size, s.status,
                    s.feedback, s.submitted_at, s.created_at, s.updated_at,
                    u.name as student_name, c.name as class_name, sub.name as subject_name
            FROM assignment_submissions s
            JOIN users u ON u.id = s.student_id
            JOIN classes c ON c.id = s.class_id
            JOIN subjects sub ON sub.id = s.subject_id
            $where
            ORDER BY s.submitted_at DESC"
        );
        $stmt->execute($params);
        $submissions = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'success' => true,
            'submissions' => $submissions
        ]);

    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to fetch submissions: ' . $e->getMessage()]);
    }
}


// Function to refresh user session
function refreshUserSession($pdo, $input) {
    if (!isset($input['user_id'])) {
        http_response_code(400);
        echo json_encode(['error' => 'User ID is required']);
        return;
    }
    
    $userId = $input['user_id'];
    
    try {
        $stmt = $pdo->prepare("SELECT id, name, email, role FROM users WHERE id = ?");
        $stmt->execute([$userId]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($user) {
            echo json_encode([
                'success' => true,
                'user' => $user
            ]);
        } else {
            http_response_code(404);
            echo json_encode(['error' => 'User not found']);
        }
    } catch (PDOException $e) {
        http_response_code(500);
        echo json_encode(['error' => 'Failed to refresh session: ' . $e->getMessage()]);
    }
} 
