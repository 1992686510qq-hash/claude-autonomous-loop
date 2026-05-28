// Ralph Auto Runner - 飞书通知器
// 监控 checkpoint.json，每完成一个 story 发飞书通知
//
// 用法: node notifier.js
// 依赖: lark-cli (npm install -g @anthropic-ai/lark-cli)
//
// 环境变量:
//   CHAT_ID - 飞书群聊 ID（必填）
//   CHECKPOINT_FILE - checkpoint.json 路径（可选）
//   PRD_FILE - prd.json 路径（可选）
//   STATE_FILE - 状态文件路径（可选）

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// 配置
const CHAT_ID = process.env.CHAT_ID || '';
const PROJECT_DIR = path.resolve(__dirname, '..');
const CHECKPOINT_FILE = process.env.CHECKPOINT_FILE || path.join(PROJECT_DIR, 'checkpoint.json');
const PRD_FILE = process.env.PRD_FILE || path.join(PROJECT_DIR, 'prd.json');
const STATE_FILE = process.env.STATE_FILE || path.join(PROJECT_DIR, '.notifier-state');
const TITLE_MAP_FILE = process.env.TITLE_MAP_FILE || path.join(PROJECT_DIR, 'title-map.json');

// 中文标题映射表（可选，解决 JSON 编码损坏问题）
let TITLE_MAP = {};
try {
  TITLE_MAP = JSON.parse(fs.readFileSync(TITLE_MAP_FILE, 'utf8'));
} catch (e) {
  // 没有映射表，使用 prd.json 中的标题
}

function readJSON(filePath) {
  try {
    let raw = fs.readFileSync(filePath);
    // Strip BOM
    if (raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF) raw = raw.slice(3);
    if (raw[0] === 0xFE) raw = raw.slice(2);
    return JSON.parse(raw.toString('utf8'));
  } catch (e) {
    return null;
  }
}

function getState() {
  try { return parseInt(fs.readFileSync(STATE_FILE, 'utf8').trim()) || 0; }
  catch (e) { return 0; }
}

function setState(n) {
  fs.writeFileSync(STATE_FILE, String(n), 'utf8');
}

function sendMsg(text) {
  if (!CHAT_ID) {
    console.error('[notifier] CHAT_ID 未设置，跳过通知');
    return;
  }
  try {
    const escaped = text.replace(/"/g, '\\"').replace(/\n/g, '\\n');
    execSync(`lark-cli im +messages-send --chat-id "${CHAT_ID}" --text "${escaped}" --as bot`, {
      stdio: 'pipe',
      timeout: 15000
    });
  } catch (e) {
    console.error('[notifier] 发送失败:', e.message);
  }
}

function main() {
  const cp = readJSON(CHECKPOINT_FILE);
  const prd = readJSON(PRD_FILE);
  if (!cp) { console.error('[notifier] checkpoint.json 读取失败'); return; }

  const stories = (prd && (prd.userStories || prd.stories)) || [];
  const cpKeys = Object.keys(cp).sort();
  const total = stories.length || '?';
  const current = cpKeys.length;
  const known = getState();

  if (current <= known) {
    // 无新完成
    return;
  }

  const newKeys = cpKeys.slice(known);
  let seq = known;

  for (const id of newKeys) {
    seq++;
    const story = stories.find(s => s.id === id);
    const title = TITLE_MAP[id] || (story ? story.title : id);
    const output = cp[id].output || '';

    const now = new Date();
    const timeStr = now.toLocaleTimeString('zh-CN', { hour12: false });

    const msg = [
      `✅ 任务完成 [${seq}/${total}]`,
      `📌 ${id}: ${title}`,
      output ? `📁 输出: ${output}` : '',
      `⏰ ${timeStr}`
    ].filter(Boolean).join('\n');

    console.log(`[notifier] ${id} - ${title}`);
    sendMsg(msg);
  }

  setState(current);

  // 全部完成
  if (total !== '?' && current >= total) {
    sendMsg(`🎉 全部完成！${current}/${total} 个任务已执行完毕。`);
  }
}

main();
