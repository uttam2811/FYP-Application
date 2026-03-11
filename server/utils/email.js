const nodemailer = require('nodemailer');
const crypto = require('crypto');
require('dotenv').config();

// Create reusable transporter
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS
  }
});

// Generate a 6-digit OTP
function generateOTP() {
  return crypto.randomInt(100000, 999999).toString();
}

// Send OTP email
async function sendOTPEmail(toEmail, otp, purpose = 'login') {
  const subjects = {
    login: 'Your Login OTP — FYP Application',
    register: 'Verify Your Email — FYP Application'
  };

  const messages = {
    login: `
      <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px; background: #ffffff; border-radius: 16px; border: 1px solid #e2e8f0;">
        <div style="text-align: center; margin-bottom: 24px;">
          <div style="font-size: 2.5rem;">📡</div>
          <h1 style="color: #1e293b; font-size: 1.4rem; margin: 8px 0;">FYP Application</h1>
          <p style="color: #64748b; font-size: 0.9rem;">Login Verification</p>
        </div>
        <div style="background: #f1f5f9; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0;">
          <p style="color: #64748b; font-size: 0.85rem; margin-bottom: 8px;">Your One-Time Password</p>
          <div style="font-size: 2.2rem; font-weight: 700; color: #2563eb; letter-spacing: 8px; font-family: 'Consolas', monospace;">${otp}</div>
        </div>
        <p style="color: #64748b; font-size: 0.85rem; text-align: center;">
          This OTP is valid for <strong>${process.env.OTP_EXPIRY_MINUTES || 5} minutes</strong>.<br>
          Do not share this code with anyone.
        </p>
        <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 20px 0;">
        <p style="color: #94a3b8; font-size: 0.75rem; text-align: center;">
          If you didn't request this, please ignore this email.
        </p>
      </div>
    `,
    register: `
      <div style="font-family: 'Segoe UI', Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 32px; background: #ffffff; border-radius: 16px; border: 1px solid #e2e8f0;">
        <div style="text-align: center; margin-bottom: 24px;">
          <div style="font-size: 2.5rem;">📡</div>
          <h1 style="color: #1e293b; font-size: 1.4rem; margin: 8px 0;">FYP Application</h1>
          <p style="color: #64748b; font-size: 0.9rem;">Email Verification</p>
        </div>
        <div style="background: #f1f5f9; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0;">
          <p style="color: #64748b; font-size: 0.85rem; margin-bottom: 8px;">Your Verification Code</p>
          <div style="font-size: 2.2rem; font-weight: 700; color: #16a34a; letter-spacing: 8px; font-family: 'Consolas', monospace;">${otp}</div>
        </div>
        <p style="color: #64748b; font-size: 0.85rem; text-align: center;">
          Enter this code to complete your registration.<br>
          Valid for <strong>${process.env.OTP_EXPIRY_MINUTES || 5} minutes</strong>.
        </p>
        <hr style="border: none; border-top: 1px solid #e2e8f0; margin: 20px 0;">
        <p style="color: #94a3b8; font-size: 0.75rem; text-align: center;">
          If you didn't create an account, please ignore this email.
        </p>
      </div>
    `
  };

  const mailOptions = {
    from: `"FYP Application" <${process.env.EMAIL_FROM}>`,
    to: toEmail,
    subject: subjects[purpose] || subjects.login,
    html: messages[purpose] || messages.login
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log(`[Email] OTP sent to ${toEmail} for ${purpose}: ${info.messageId}`);
    return { success: true, messageId: info.messageId };
  } catch (error) {
    console.error(`[Email] Failed to send OTP to ${toEmail}:`, error.message);
    return { success: false, error: error.message };
  }
}

module.exports = { generateOTP, sendOTPEmail };
