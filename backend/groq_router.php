<?php
declare(strict_types=1);

$isCli = php_sapi_name() === 'cli';

function sendResponse(array $payload, int $statusCode = 200): void
{
    global $isCli;

    if ($isCli) {
        $encoded = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        echo ($encoded === false ? '{"success":false,"message":"Failed to encode response"}' : $encoded) . PHP_EOL;
        return;
    }

    if (!headers_sent()) {
        header('Access-Control-Allow-Origin: *');
        header('Content-Type: application/json; charset=UTF-8');
        header('Access-Control-Allow-Methods: POST, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
    }

    http_response_code($statusCode);
    $encoded = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    echo $encoded === false ? '{"success":false,"message":"Failed to encode response"}' : $encoded;
    exit;
}

function routeModel(string $task): string
{
    switch ($task) {
        case 'summarize':
            return 'mixtral-8x7b';
        case 'deep_reasoning':
            return 'llama-3.3-70b-versatile';
        case 'quick_extract':
            return 'llama-3.1-8b-instant';
        case 'tool_use':
            return 'llama-3-groq-8b-tool-use';
        default:
            return 'llama-3.1-8b-instant';
    }
}

function fallbackModel(string $task): string
{
    switch ($task) {
        case 'summarize':
            return 'llama-3.1-8b-instant';
        case 'deep_reasoning':
            return 'mixtral-8x7b';
        case 'quick_extract':
            return 'gemma-7b';
        case 'tool_use':
            return 'llama-3.3-70b-versatile';
        default:
            return 'gemma-7b';
    }
}

function callGroq(string $model, array $messages, string $apiKey): array
{
    $payload = json_encode([
        'model' => $model,
        'messages' => $messages,
    ]);

    if ($payload === false) {
        return [false, 'Failed to encode request payload'];
    }

    $ch = curl_init('https://api.groq.com/openai/v1/chat/completions');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $apiKey,
            'Content-Type: application/json',
        ],
        CURLOPT_TIMEOUT => 60,
    ]);

    $response = curl_exec($ch);
    $error = curl_error($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($response === false) {
        return [false, 'cURL error: ' . ($error ?: 'Unknown error'), null, $status];
    }

    $decoded = json_decode($response, true);
    if ($decoded === null) {
        return [false, 'Invalid JSON response from Groq', $response, $status];
    }

    return [true, $decoded, null, $status];
}

function extractReply(array $groqResponse): ?string
{
    return $groqResponse['choices'][0]['message']['content'] ?? null;
}

function handleChat(string $message, string $task, string $apiKey): array
{
    $messages = [
        ['role' => 'system', 'content' => 'You are a helpful assistant.'],
        ['role' => 'user', 'content' => $message],
    ];

    $primaryModel = routeModel($task);
    [$ok, $primaryResponse, $rawFallback, $status] = callGroq($primaryModel, $messages, $apiKey);

    if ($ok) {
        $reply = extractReply($primaryResponse);
        if ($reply !== null) {
            return [true, 'Success', ['reply' => $reply, 'model' => $primaryModel]];
        }
    }

    $backupModel = fallbackModel($task);
    [$fallbackOk, $fallbackResponse, $raw, $fallbackStatus] = callGroq($backupModel, $messages, $apiKey);

    if ($fallbackOk) {
        $reply = extractReply($fallbackResponse);
        if ($reply !== null) {
            return [true, 'Success', ['reply' => $reply, 'model' => $backupModel]];
        }
    }

    $errorDetails = [
        'primary' => [
            'model' => $primaryModel,
            'status_code' => $status ?? null,
            'response' => $primaryResponse,
            'raw_fallback' => $rawFallback ?? null,
        ],
        'fallback' => [
            'model' => $backupModel,
            'status_code' => $fallbackStatus ?? null,
            'response' => $fallbackResponse ?? null,
            'raw' => $raw ?? null,
        ],
    ];

    return [false, 'Failed to generate response from Groq models.', $errorDetails];
}

$apiKey = getenv('GROQ_API_KEY');
if (!$apiKey) {
    sendResponse([
        'success' => false,
        'message' => 'GROQ_API_KEY environment variable is not set.',
    ], 500);
}

if ($isCli) {
    global $argv;
    $message = $argv[1] ?? '';
    $task = $argv[2] ?? 'default';

    if (trim($message) === '') {
        sendResponse([
            'success' => false,
            'message' => 'Usage: php groq_router.php "<message>" [task]',
            'tasks' => ['summarize', 'deep_reasoning', 'quick_extract', 'tool_use', 'default'],
        ], 400);
        return;
    }

    [$ok, $msg, $data] = handleChat($message, $task, $apiKey);
    sendResponse([
        'success' => $ok,
        'message' => $msg,
        'data' => $data,
    ], $ok ? 200 : 502);
    return;
}

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    sendResponse([
        'success' => true,
        'message' => 'Preflight OK',
    ]);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse([
        'success' => false,
        'message' => 'Only POST method is allowed.',
    ], 405);
}

$input = file_get_contents('php://input');
$decodedInput = json_decode($input, true);

if (!is_array($decodedInput)) {
    sendResponse([
        'success' => false,
        'message' => 'Invalid JSON payload.',
    ], 400);
}

$message = trim((string)($decodedInput['message'] ?? ''));
$task = (string)($decodedInput['task'] ?? 'default');

if ($message === '') {
    sendResponse([
        'success' => false,
        'message' => 'The "message" field is required.',
    ], 400);
}

[$ok, $msg, $data] = handleChat($message, $task, $apiKey);

sendResponse([
    'success' => $ok,
    'message' => $msg,
    'data' => $data,
], $ok ? 200 : 502);

