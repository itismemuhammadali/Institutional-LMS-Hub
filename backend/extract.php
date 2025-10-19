<?php
require __DIR__ . '/vendor/autoload.php';

$filename = $_GET['file'] ?? '';

if (!$filename || !file_exists(__DIR__ . "/uploads/$filename")) {
    echo json_encode(["error" => "File not found"]);
    exit;
}

$ext = pathinfo($filename, PATHINFO_EXTENSION);
$filePath = __DIR__ . "/uploads/$filename";
$output = "";

switch (strtolower($ext)) {
    case 'pdf':
        $parser = new Smalot\PdfParser\Parser();
        $pdf = $parser->parseFile($filePath);
        $output = $pdf->getText();
        break;

    case 'xlsx':
    case 'xls':
        $spreadsheet = \PhpOffice\PhpSpreadsheet\IOFactory::load($filePath);
        foreach ($spreadsheet->getActiveSheet()->toArray() as $row) {
            $output .= implode(" | ", $row) . "\n";
        }
        break;

    case 'docx':
        $phpWord = \PhpOffice\PhpWord\IOFactory::load($filePath);
        foreach ($phpWord->getSections() as $section) {
            foreach ($section->getElements() as $element) {
                if (method_exists($element, "getText")) {
                    $output .= $element->getText() . "\n";
                }
            }
        }
        break;

    case 'pptx':
        $pptReader = \PhpOffice\PhpPresentation\IOFactory::createReader('PowerPoint2007');
        $presentation = $pptReader->load($filePath);
        foreach ($presentation->getAllSlides() as $slide) {
            foreach ($slide->getShapeCollection() as $shape) {
                if ($shape instanceof \PhpOffice\PhpPresentation\Shape\RichText) {
                    foreach ($shape->getParagraphs() as $paragraph) {
                        foreach ($paragraph->getRichTextElements() as $element) {
                            $output .= $element->getText() . " ";
                        }
                    }
                }
            }
        }
        break;

    default:
        $output = file_get_contents($filePath);
        break;
}

echo json_encode(["content" => $output]);
