<?php
/**
 * 皇雅官网 — 咨询表单邮件发送
 * SMTP: 阿里云企业邮箱
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['success' => false, 'message' => 'Method not allowed']);
    exit;
}

// ==================== CONFIG ====================
$SMTP_HOST  = 'smtp.mxhichina.com';
$SMTP_PORT  = 465;
$SMTP_USER  = 'vip@snhanyue.com';
$SMTP_PASS  = 'Xl210123';
$MAIL_TO    = 'huangya@snhanyue.com';
$MAIL_FROM  = 'vip@snhanyue.com';
$MAIL_FROM_NAME = '皇雅官网';

// ==================== GET FORM DATA ====================
$input = json_decode(file_get_contents('php://input'), true);

$name    = trim($input['name'] ?? '');
$phone   = trim($input['phone'] ?? '');
$city    = trim($input['city'] ?? '');
$type    = trim($input['type'] ?? '');
$notes   = trim($input['notes'] ?? '');

if (empty($name) || empty($phone)) {
    echo json_encode(['success' => false, 'message' => '请填写必填字段']);
    exit;
}

// ==================== BUILD EMAIL ====================
$subject = "【皇雅官网咨询】{$name} - {$phone}";

$body = <<<HTML
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family: 'PingFang SC', 'Microsoft YaHei', sans-serif; background: #f5f5f5; padding: 20px;">
<div style="max-width: 600px; margin: 0 auto; background: #fff; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.1);">
  <div style="background: linear-gradient(135deg, #C4A67A, #A88B60); padding: 24px 30px; color: #fff;">
    <h2 style="margin: 0; font-size: 20px;">📩 新客户咨询</h2>
    <p style="margin: 8px 0 0; opacity: 0.9; font-size: 14px;">来自皇雅系统门窗官网</p>
  </div>
  <div style="padding: 30px;">
    <table style="width: 100%; border-collapse: collapse;">
      <tr>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #999; width: 90px; font-size: 14px;">姓名</td>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-size: 15px; font-weight: 600;">{$name}</td>
      </tr>
      <tr>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #999; font-size: 14px;">联系电话</td>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-size: 15px; font-weight: 600;">
          <a href="tel:{$phone}" style="color: #C4A67A; text-decoration: none;">{$phone}</a>
        </td>
      </tr>
      <tr>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #999; font-size: 14px;">所在城市</td>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-size: 15px;">{$city}</td>
      </tr>
      <tr>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; color: #999; font-size: 14px;">需求类型</td>
        <td style="padding: 12px 0; border-bottom: 1px solid #eee; font-size: 15px;">{$type}</td>
      </tr>
      <tr>
        <td style="padding: 12px 0; color: #999; font-size: 14px; vertical-align: top;">补充说明</td>
        <td style="padding: 12px 0; font-size: 15px; line-height: 1.6;">{$notes}</td>
      </tr>
    </table>
  </div>
  <div style="padding: 16px 30px; background: #fafaf8; border-top: 1px solid #eee; font-size: 12px; color: #999;">
    提交时间：{$input['timestamp']} &nbsp;|&nbsp; 来源：皇雅官网
  </div>
</div>
</body>
</html>
HTML;

// ==================== SEND VIA SMTP ====================
$result = sendSmtpMail($SMTP_HOST, $SMTP_PORT, $SMTP_USER, $SMTP_PASS, $MAIL_FROM, $MAIL_FROM_NAME, $MAIL_TO, $subject, $body);

if ($result === true) {
    $logDir = __DIR__ . '/logs';
    if (!is_dir($logDir)) mkdir($logDir, 0755, true);
    $logEntry = date('Y-m-d H:i:s') . " | {$name} | {$phone} | {$city} | {$type} | {$notes}\n";
    file_put_contents($logDir . '/inquiries.log', $logEntry, FILE_APPEND | LOCK_EX);

    echo json_encode(['success' => true, 'message' => '提交成功']);
} else {
    echo json_encode(['success' => false, 'message' => $result]);
}

// ==================== SMTP FUNCTION ====================
function sendSmtpMail($host, $port, $user, $pass, $from, $fromName, $to, $subject, $htmlBody) {
    $errno = 0;
    $errstr = '';

    $smtp = @fsockopen("ssl://{$host}", $port, $errno, $errstr, 15);
    if (!$smtp) {
        return "连接SMTP失败: {$errstr} ({$errno})";
    }

    stream_set_timeout($smtp, 15);

    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '220') return "SMTP连接异常: {$resp}";

    fwrite($smtp, "EHLO huangyamc.com\r\n");
    $resp = '';
    while ($line = fgets($smtp, 512)) {
        $resp .= $line;
        if (substr($line, 3, 1) === ' ') break;
    }

    fwrite($smtp, "AUTH LOGIN\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '334') return "AUTH失败: {$resp}";

    fwrite($smtp, base64_encode($user) . "\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '334') return "用户名错误: {$resp}";

    fwrite($smtp, base64_encode($pass) . "\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '235') return "密码错误: {$resp}";

    fwrite($smtp, "MAIL FROM:<{$from}>\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '250') return "MAIL FROM失败: {$resp}";

    fwrite($smtp, "RCPT TO:<{$to}>\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '250') return "RCPT TO失败: {$resp}";

    fwrite($smtp, "DATA\r\n");
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '354') return "DATA失败: {$resp}";

    $boundary = md5(uniqid(time()));
    $headers  = "From: =?UTF-8?B?" . base64_encode($fromName) . "?= <{$from}>\r\n";
    $headers .= "To: <{$to}>\r\n";
    $headers .= "Subject: =?UTF-8?B?" . base64_encode($subject) . "?=\r\n";
    $headers .= "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: text/html; charset=UTF-8\r\n";
    $headers .= "Content-Transfer-Encoding: base64\r\n";
    $headers .= "Date: " . date('r') . "\r\n";
    $headers .= "X-Mailer: HuangYa-Website\r\n";
    $headers .= "\r\n";
    $headers .= chunk_split(base64_encode($htmlBody));
    $headers .= "\r\n.\r\n";

    fwrite($smtp, $headers);
    $resp = fgets($smtp, 512);
    if (substr($resp, 0, 3) !== '250') return "发送失败: {$resp}";

    fwrite($smtp, "QUIT\r\n");
    fclose($smtp);

    return true;
}
