<?php
require __DIR__ . '/vendor/autoload.php';

use Smalot\PdfParser\Parser;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Dompdf\Dompdf;

// ---------------------
// 1) PDF Extraction
// ---------------------
$parser = new Parser();
$pdf = $parser->parseFile(__DIR__ . '/Muhammad Ali.pdf'); // make sure file exists
$text = $pdf->getText();
echo "<h3>Extracted Text from PDF:</h3>";
echo nl2br($text); // display extracted text with line breaks

// ---------------------
// 2) Excel Export
// ---------------------
$spreadsheet = new Spreadsheet();
$sheet = $spreadsheet->getActiveSheet();
$sheet->setCellValue('A1', 'Hello World!');

$writer = new Xlsx($spreadsheet);
$writer->save(__DIR__ . '/hello_world.xlsx'); // save in backend folder
echo "<br><br><strong>Excel file saved as hello_world.xlsx</strong><br>";

// ---------------------
// 3) PDF Generation
// ---------------------
$dompdf = new Dompdf();
$dompdf->loadHtml('<h1>Hello, World!</h1>');

// (Optional) Setup paper size and orientation
$dompdf->setPaper('A4', 'portrait');

// Render HTML as PDF
$dompdf->render();

// Output the generated PDF to Browser
$dompdf->stream("document.pdf", ["Attachment" => false]);

require __DIR__ . '/vendor/autoload.php';

$client = new Google_Client();
$client->setAuthConfig(__DIR__ . '/credentials.json');
$client->addScope(Google_Service_Sheets::SPREADSHEETS);

$service = new Google_Service_Sheets($client);

$spreadsheetId = "YOUR_SPREADSHEET_ID";
$range = "Sheet1!A1:D5";
$response = $service->spreadsheets_values->get($spreadsheetId, $range);
$values = $response->getValues();

print_r($values);
