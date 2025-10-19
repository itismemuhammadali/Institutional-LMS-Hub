<?php
require __DIR__ . '/vendor/autoload.php';

$filename = $_POST['file'] ?? '';
$insertContent = $_POST['content'] ?? '';

$filePath = __DIR__ . "/uploads/$filename";
if (!file_exists($filePath)) {
    echo json_encode(["error" => "File not found"]);
    exit;
}

// Just append
file_put_contents($filePath, "\n" . $insertContent, FILE_APPEND);

echo json_encode(["success" => true, "file" => $filename]);
