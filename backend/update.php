<?php
require __DIR__ . '/vendor/autoload.php';

$filename = $_POST['file'] ?? '';
$newContent = $_POST['content'] ?? '';

$filePath = __DIR__ . "/uploads/$filename";
if (!file_exists($filePath)) {
    echo json_encode(["error" => "File not found"]);
    exit;
}

// For simplicity, overwrite with new content
file_put_contents($filePath, $newContent);

echo json_encode(["success" => true, "file" => $filename]);
