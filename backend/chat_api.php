<?php 
// Enable CORS and set JSON header
header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST");
header("Access-Control-Max-Age: 3600");
header("Access-Control-Allow-Headers: Content-Type, Access-Control-Allow-Headers, Authorization, X-Requested-With");

ini_set('display_errors', 1);
error_reporting(E_ALL);

function sendResponse($success, $message, $data = null) {
    $response = [
        'success' => $success,
        'message' => $message
    ];
    if ($data !== null) {
        $response['data'] = $data;
    }
    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        sendResponse(false, 'Only POST method is allowed');
    }

    $json = file_get_contents('php://input');
    $input = json_decode($json, true);

    if (json_last_error() !== JSON_ERROR_NONE) {
        sendResponse(false, 'Invalid JSON input');
    }

    if (empty($input['message'])) {
        sendResponse(false, 'Message is required');
    }

    $userMessage = trim($input['message']);

    // Your Hugging Face token
    $apiKey = ""; 

    // ✅ Router endpoint, not the old inference API
    $apiUrl = "https://router.huggingface.co/v1/chat/completions";

    // ✅ Payload for chat/completions endpoint
    $payload = [
        "model" => "mistralai/Mistral-7B-Instruct-v0.2:featherless-ai",
        "messages" => [
            ["role" => "user", "content" => $userMessage]
        ],
        "stream" => false
    ];

    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL => $apiUrl,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $apiKey,
        ],
        CURLOPT_TIMEOUT => 60,
        CURLOPT_SSL_VERIFYPEER => true
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $error = curl_error($ch);
    curl_close($ch);

    if ($error) {
        sendResponse(false, 'cURL Error: ' . $error);
    }

    $responseData = json_decode($response, true);

    // ✅ Parse router response correctly
    if ($httpCode === 200 && isset($responseData['choices'][0]['message']['content'])) {
        sendResponse(true, 'Success', [
            'reply' => $responseData['choices'][0]['message']['content']
        ]);
    } else {
        sendResponse(false, "API Error", [
            'huggingface_raw' => $responseData,
            'http_code' => $httpCode
        ]);
    }

} catch (Exception $e) {
    sendResponse(false, "Server Error: " . $e->getMessage());
}
?>
