<?php
require __DIR__ . '/vendor/autoload.php';

$type = $_POST['type'] ?? '';
$content = $_POST['content'] ?? '';
$filename = uniqid() . ".$type";
$filePath = __DIR__ . "/uploads/$filename";

switch ($type) {
    case 'pdf':
        $dompdf = new Dompdf\Dompdf();
        $dompdf->loadHtml("<pre>$content</pre>");
        $dompdf->render();
        file_put_contents($filePath, $dompdf->output());
        break;

    case 'xlsx':
        $spreadsheet = new PhpOffice\PhpSpreadsheet\Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();
        $rows = explode("\n", $content);
        $rowIndex = 1;
        foreach ($rows as $row) {
            $cols = explode(",", $row);
            $colIndex = 'A';
            foreach ($cols as $col) {
                $sheet->setCellValue($colIndex.$rowIndex, $col);
                $colIndex++;
            }
            $rowIndex++;
        }
        $writer = new PhpOffice\PhpSpreadsheet\Writer\Xlsx($spreadsheet);
        $writer->save($filePath);
        break;

    case 'docx':
        $phpWord = new PhpOffice\PhpWord\PhpWord();
        $section = $phpWord->addSection();
        $section->addText($content);
        $writer = \PhpOffice\PhpWord\IOFactory::createWriter($phpWord, 'Word2007');
        $writer->save($filePath);
        break;

    case 'pptx':
        $ppt = new PhpOffice\PhpPresentation\PhpPresentation();
        $currentSlide = $ppt->getActiveSlide();
        $shape = $currentSlide->createRichTextShape();
        $shape->createTextRun($content);
        $writer = \PhpOffice\PhpPresentation\IOFactory::createWriter($ppt, 'PowerPoint2007');
        $writer->save($filePath);
        break;

    default:
        file_put_contents($filePath, $content);
        break;
}

echo json_encode(["success" => true, "file" => $filename]);
