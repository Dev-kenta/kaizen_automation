#!/usr/bin/env node

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const csv = require('csv-parser');
const { execSync } = require('child_process');
const readline = require('readline');

// 定数
const REPO = 'basicinc/formrun';
const SCREENSHOTS_DIR = path.join(__dirname, 'screenshots');
const DEFAULT_CSV_FILE = path.join(__dirname, 'pr_list.csv');

/**
 * GitHub CLIから認証トークンを取得
 */
function getGitHubToken() {
  try {
    const token = execSync('gh auth token', { encoding: 'utf-8' }).trim();
    if (!token) {
      throw new Error('GitHub CLIの認証トークンが取得できませんでした');
    }
    return token;
  } catch (error) {
    console.error('エラー: GitHub CLIが認証されていません');
    console.error('以下のコマンドを実行して認証してください:');
    console.error('  gh auth login');
    process.exit(1);
  }
}

/**
 * CSVファイルからPR一覧を読み込む
 */
async function loadPRsFromCSV(csvFilePath) {
  return new Promise((resolve, reject) => {
    const prs = [];
    const seenPRs = new Set();

    if (!fs.existsSync(csvFilePath)) {
      reject(new Error(`CSVファイルが見つかりません: ${csvFilePath}`));
      return;
    }

    fs.createReadStream(csvFilePath)
      .pipe(csv({ headers: false }))
      .on('data', (row) => {
        // row は配列として取得される（headers: false のため）
        const values = Object.values(row);

        // 各カラムから #数字 の形式を探す
        for (let value of values) {
          if (typeof value === 'string') {
            const match = value.match(/#(\d+)/);
            if (match) {
              const prNumber = match[1];
              // 重複を避ける
              if (!seenPRs.has(prNumber)) {
                seenPRs.add(prNumber);
                prs.push({
                  number: prNumber,
                  rawData: values.join(',')
                });
              }
              break; // 1行につき1つのPRを見つけたらループを抜ける
            }
          }
        }
      })
      .on('end', () => {
        console.log(`${prs.length}件のPRをCSVから読み込みました`);
        resolve(prs);
      })
      .on('error', (error) => {
        reject(error);
      });
  });
}

/**
 * PRのスクリーンショットを撮影
 */
async function screenshotPR(context, prNumber) {
  const page = await context.newPage();
  const url = `https://github.com/${REPO}/pull/${prNumber}`;

  try {
    console.log(`  アクセス中: ${url}`);

    // ページにアクセス（タイムアウトを60秒に設定）
    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 60000
    });

    // ページの読み込みを待機（複数のセレクタを試す）
    try {
      await page.waitForSelector('#partial-discussion-header, .gh-header-title, h1.js-issue-title, [data-hpc]', {
        timeout: 15000,
        state: 'visible'
      });
    } catch (waitError) {
      // セレクタが見つからなくても、少し待ってからスクリーンショットを撮る
      console.log(`  ⚠ セレクタ待機タイムアウト、3秒待機後にスクリーンショット撮影`);
      await page.waitForTimeout(3000);
    }

    // ページが認証エラーかチェック
    const isLoginPage = await page.locator('input[name="login"]').count() > 0;
    if (isLoginPage) {
      throw new Error('認証が必要です。GitHubにログインしてください。');
    }

    // スクリーンショットを撮影
    const screenshotPath = path.join(SCREENSHOTS_DIR, `pr-${prNumber}.png`);
    await page.screenshot({
      path: screenshotPath,
      fullPage: true
    });

    console.log(`  ✓ 保存完了: ${screenshotPath}`);
    return { success: true, path: screenshotPath };

  } catch (error) {
    console.error(`  ✗ エラー: ${error.message}`);
    return { success: false, error: error.message };

  } finally {
    await page.close();
  }
}

/**
 * メイン処理
 */
async function main() {
  // コマンドライン引数からCSVファイルパスを取得
  const csvFilePath = process.argv[2] || DEFAULT_CSV_FILE;

  console.log('=== GitHub PR スクリーンショットツール ===\n');

  // スクリーンショット保存ディレクトリを作成
  if (!fs.existsSync(SCREENSHOTS_DIR)) {
    fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  }

  // GitHub CLI が認証されているか確認
  console.log('GitHub CLIの認証確認中...');
  try {
    getGitHubToken();
    console.log('✓ GitHub CLIは認証されています\n');
  } catch (error) {
    console.log('⚠ GitHub CLIが認証されていませんが、ブラウザで手動ログインできます\n');
  }

  // CSVからPR一覧を読み込み
  console.log(`CSVファイルを読み込み中: ${csvFilePath}`);
  let prs;
  try {
    prs = await loadPRsFromCSV(csvFilePath);
  } catch (error) {
    console.error(`エラー: ${error.message}`);
    process.exit(1);
  }

  if (prs.length === 0) {
    console.log('処理対象のPRがありません');
    process.exit(0);
  }

  // ブラウザを起動（認証状態を保存するためのディレクトリを指定）
  console.log('\nブラウザを起動中...');
  const userDataDir = path.join(__dirname, '.browser-data');

  const browser = await chromium.launchPersistentContext(userDataDir, {
    headless: false,  // 初回は手動ログインが必要な場合があるため
    viewport: { width: 1920, height: 1080 }
  });

  console.log('✓ ブラウザを起動しました');
  console.log('※ 初回実行時はGitHubログインが必要な場合があります\n');

  // GitHubにログインしているか確認
  console.log('GitHub認証状態を確認中...');
  const testPage = await browser.newPage();
  await testPage.goto('https://github.com/login', { waitUntil: 'domcontentloaded', timeout: 30000 });

  const isLoggedIn = await testPage.evaluate(() => {
    // ログイン済みの場合は /login にアクセスするとリダイレクトされる
    return !window.location.pathname.includes('/login');
  });

  if (!isLoggedIn) {
    console.log('\n⚠ GitHubにログインが必要です');
    console.log('ブラウザが開いたら、GitHubにログインしてください');
    console.log('ログイン完了後、Enterキーを押してください...\n');

    // ユーザーの入力を待つ
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    await new Promise((resolve) => {
      rl.question('', () => {
        rl.close();
        resolve();
      });
    });

    // ログイン状態を再確認
    await testPage.reload({ waitUntil: 'domcontentloaded' });
    const isNowLoggedIn = await testPage.evaluate(() => {
      return !window.location.pathname.includes('/login');
    });

    if (!isNowLoggedIn) {
      console.error('\nエラー: まだログインされていません');
      await testPage.close();
      await browser.close();
      process.exit(1);
    }
    console.log('✓ ログイン確認完了\n');
  } else {
    console.log('✓ GitHub認証済み\n');
  }

  await testPage.close();

  // 統計情報
  const stats = {
    total: prs.length,
    success: 0,
    failed: 0,
    errors: []
  };

  // 各PRのスクリーンショットを順次撮影
  console.log('\nスクリーンショット撮影を開始します...\n');

  for (let i = 0; i < prs.length; i++) {
    const pr = prs[i];
    console.log(`[${i + 1}/${prs.length}] PR #${pr.number}`);

    const result = await screenshotPR(browser, pr.number);

    if (result.success) {
      stats.success++;
    } else {
      stats.failed++;
      stats.errors.push({
        prNumber: pr.number,
        error: result.error
      });
    }

    // 次のリクエストまで少し待機（GitHub APIのレート制限対策）
    if (i < prs.length - 1) {
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }

  await browser.close();

  // 結果サマリーを表示
  console.log('\n=== 処理完了 ===');
  console.log(`総数: ${stats.total}`);
  console.log(`成功: ${stats.success}`);
  console.log(`失敗: ${stats.failed}`);

  if (stats.errors.length > 0) {
    console.log('\n失敗したPR:');
    stats.errors.forEach(({ prNumber, error }) => {
      console.log(`  - PR #${prNumber}: ${error}`);
    });
  }

  console.log(`\nスクリーンショットは以下に保存されました:`);
  console.log(`  ${SCREENSHOTS_DIR}/`);

  // PDF生成（成功したスクリーンショットが1件以上ある場合）
  if (stats.success > 0) {
    console.log('\n--- PDF生成 ---');
    console.log('スクリーンショットからPDFを生成しています...\n');

    try {
      // create_pdf.jsを実行
      const createPdfScript = path.join(__dirname, 'create_pdf.js');
      execSync(`node "${createPdfScript}"`, {
        stdio: 'inherit',
        encoding: 'utf-8'
      });
    } catch (error) {
      console.error('\nPDF生成でエラーが発生しました:', error.message);
      console.log('スクリーンショットは正常に保存されています。');
    }
  }
}

// スクリプト実行
main().catch(error => {
  console.error('予期しないエラーが発生しました:', error);
  process.exit(1);
});
