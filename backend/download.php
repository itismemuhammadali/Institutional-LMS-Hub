<?php
$filename = $_GET['file'] ?? '';
$filePath = __DIR__ . "/uploads/$filename";

if (file_exists($filePath)) {
    header('Content-Description: File Transfer');
    header('Content-Type: application/octet-stream');
    header('Content-Disposition: attachment; filename="'.basename($filePath).'"');
    readfile($filePath);
    exit;
} else {
    echo "File not found.";
}
