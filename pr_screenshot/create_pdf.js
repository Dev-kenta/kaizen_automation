#!/usr/bin/env node

const { PDFDocument } = require('pdf-lib');
const fs = require('fs');
const path = require('path');

// 定数
const SCREENSHOTS_DIR = path.join(__dirname, 'screenshots');
const PDFS_DIR = path.join(__dirname, 'pdfs');

/**
 * スクリーンショットファイルを取得してソート
 */
function getScreenshotFiles() {
  if (!fs.existsSync(SCREENSHOTS_DIR)) {
    throw new Error(`スクリーンショットディレクトリが見つかりません: ${SCREENSHOTS_DIR}`);
  }

  const files = fs.readdirSync(SCREENSHOTS_DIR)
    .filter(file => file.endsWith('.png') && file.startsWith('pr-'))
    .map(file => {
      // pr-15703.png -> 15703
      const match = file.match(/pr-(\d+)\.png/);
      return {
        filename: file,
        prNumber: match ? parseInt(match[1]) : 0,
        fullPath: path.join(SCREENSHOTS_DIR, file)
      };
    })
    .sort((a, b) => a.prNumber - b.prNumber);

  return files;
}

/**
 * 1つのスクリーンショットから個別PDFを作成
 */
async function createSinglePDF(file) {
  // 個別PDFを作成
  const pdfDoc = await PDFDocument.create();

  // 画像を読み込み
  const imageBytes = fs.readFileSync(file.fullPath);
  const image = await pdfDoc.embedPng(imageBytes);

  // 画像のサイズを取得
  const { width, height } = image.scale(1);

  // A4サイズに合わせてスケール調整（横595pt、縦842pt）
  const maxWidth = 595;
  const maxHeight = 842;

  let scale = 1;
  if (width > maxWidth) {
    scale = maxWidth / width;
  }

  const scaledWidth = width * scale;
  const scaledHeight = height * scale;

  // ページを追加（画像サイズに合わせる）
  const page = pdfDoc.addPage([scaledWidth, scaledHeight]);

  // 画像を配置
  page.drawImage(image, {
    x: 0,
    y: 0,
    width: scaledWidth,
    height: scaledHeight,
  });

  // PDFを保存
  const outputPath = path.join(PDFS_DIR, `pr-${file.prNumber}.pdf`);
  const pdfBytes = await pdfDoc.save();
  fs.writeFileSync(outputPath, pdfBytes);

  return outputPath;
}

/**
 * 全スクリーンショットから個別PDFを作成
 */
async function createPDFs() {
  console.log('=== GitHub PR スクリーンショット PDF生成ツール ===\n');

  // PDFディレクトリを作成
  if (!fs.existsSync(PDFS_DIR)) {
    fs.mkdirSync(PDFS_DIR, { recursive: true });
    console.log(`PDF保存ディレクトリを作成しました: ${PDFS_DIR}\n`);
  }

  // スクリーンショットファイルを取得
  console.log('スクリーンショットファイルを読み込み中...');
  const files = getScreenshotFiles();

  if (files.length === 0) {
    console.log('スクリーンショットが見つかりません');
    console.log(`ディレクトリ: ${SCREENSHOTS_DIR}`);
    process.exit(0);
  }

  console.log(`${files.length}件のスクリーンショットを見つけました\n`);

  // 統計情報
  const stats = {
    total: files.length,
    success: 0,
    failed: 0
  };

  // 各画像から個別PDFを作成
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    console.log(`[${i + 1}/${files.length}] PR #${file.prNumber} のPDF作成中...`);

    try {
      const outputPath = await createSinglePDF(file);
      console.log(`  ✓ 完了: ${path.basename(outputPath)}`);
      stats.success++;
    } catch (error) {
      console.error(`  ✗ エラー: ${error.message}`);
      stats.failed++;
    }
  }

  console.log('\n=== PDF生成完了 ===');
  console.log(`総数: ${stats.total}`);
  console.log(`成功: ${stats.success}`);
  console.log(`失敗: ${stats.failed}`);
  console.log(`\n保存先: ${PDFS_DIR}/`);
}

// スクリプト実行
createPDFs().catch(error => {
  console.error('予期しないエラーが発生しました:', error);
  process.exit(1);
});
