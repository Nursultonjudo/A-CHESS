// SMS yuborish moduli. Provayderni SMS_PROVIDER muhit o'zgaruvchisi bilan tanlaymiz.
//
//   SMS_PROVIDER=console  -> test rejimi: kod faqat server logiga yoziladi
//   SMS_PROVIDER=http     -> istalgan HTTP-API li provayder (quyidagi sozlamalar bilan)
//
// HTTP rejimi uchun:
//   SMS_API_URL    - provayder manzili (POST)
//   SMS_API_TOKEN  - Bearer token
// Provayder boshqacha format talab qilsa, faqat sendViaHttp funksiyasini o'zgartirasiz.

export const provider = process.env.SMS_PROVIDER || 'console';
export const isTestMode = provider === 'console';

async function sendViaHttp(phone, text) {
  const url = process.env.SMS_API_URL;
  if (!url) throw new Error('SMS_API_URL sozlanmagan');

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${process.env.SMS_API_TOKEN || ''}`,
    },
    body: JSON.stringify({ phone, text }),
  });
  if (!res.ok) throw new Error(`SMS provayder xatosi: ${res.status}`);
}

export async function sendSms(phone, text) {
  if (provider === 'console') {
    console.log(`[SMS test] ${phone}: ${text}`);
    return;
  }
  if (provider === 'http') {
    return sendViaHttp(phone, text);
  }
  throw new Error(`Noma'lum SMS provayder: ${provider}`);
}
