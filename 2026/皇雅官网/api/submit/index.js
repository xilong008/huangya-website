import nodemailer from 'nodemailer'

export const config = {
  runtime: 'nodejs'
}

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type')

  if (req.method === 'OPTIONS') {
    return res.status(200).end()
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, message: 'Method not allowed' })
  }

  const { name, phone, city, type, notes, timestamp } = req.body

  if (!name || !phone) {
    return res.status(400).json({ success: false, message: '请填写必填字段' })
  }

  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.mxhichina.com',
    port: parseInt(process.env.SMTP_PORT || '465'),
    secure: true,
    auth: {
      user: process.env.SMTP_USER || 'vip@snhanyue.com',
      pass: process.env.SMTP_PASS || 'Xl210123'
    }
  })

  const subject = `【皇雅官网咨询】${name} - ${phone}`

  const htmlBody = `<!DOCTYPE html>
<html><head><meta charset="utf-8"></head>
<body style="font-family:'PingFang SC','Microsoft YaHei',sans-serif;background:#f5f5f5;padding:20px;">
<div style="max-width:600px;margin:0 auto;background:#fff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.1);">
  <div style="background:linear-gradient(135deg,#C4A67A,#A88B60);padding:24px 30px;color:#fff;">
    <h2 style="margin:0;font-size:20px;">📩 新客户咨询</h2>
    <p style="margin:8px 0 0;opacity:0.9;font-size:14px;">来自皇雅系统门窗官网</p>
  </div>
  <div style="padding:30px;">
    <table style="width:100%;border-collapse:collapse;">
      <tr><td style="padding:12px 0;border-bottom:1px solid #eee;color:#999;width:90px;font-size:14px;">姓名</td><td style="padding:12px 0;border-bottom:1px solid #eee;font-size:15px;font-weight:600;">${name}</td></tr>
      <tr><td style="padding:12px 0;border-bottom:1px solid #eee;color:#999;font-size:14px;">联系电话</td><td style="padding:12px 0;border-bottom:1px solid #eee;font-size:15px;font-weight:600;"><a href="tel:${phone}" style="color:#C4A67A;text-decoration:none;">${phone}</a></td></tr>
      <tr><td style="padding:12px 0;border-bottom:1px solid #eee;color:#999;font-size:14px;">所在城市</td><td style="padding:12px 0;border-bottom:1px solid #eee;font-size:15px;">${city || ''}</td></tr>
      <tr><td style="padding:12px 0;border-bottom:1px solid #eee;color:#999;font-size:14px;">需求类型</td><td style="padding:12px 0;border-bottom:1px solid #eee;font-size:15px;">${type || ''}</td></tr>
      <tr><td style="padding:12px 0;color:#999;font-size:14px;vertical-align:top;">补充说明</td><td style="padding:12px 0;font-size:15px;line-height:1.6;">${notes || ''}</td></tr>
    </table>
  </div>
  <div style="padding:16px 30px;background:#fafaf8;border-top:1px solid #eee;font-size:12px;color:#999;">
    提交时间：${timestamp || ''} &nbsp;|&nbsp; 来源：皇雅官网
  </div>
</div></body></html>`

  try {
    await transporter.sendMail({
      from: `"皇雅官网" <vip@snhanyue.com>`,
      to: process.env.MAIL_TO || 'huangya@snhanyue.com',
      subject,
      html: htmlBody
    })

    return res.status(200).json({ success: true, message: '提交成功' })
  } catch (err) {
    console.error('Email send error:', err.message)
    return res.status(500).json({ success: false, message: '邮件发送失败' })
  }
}
