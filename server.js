import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { GoogleGenAI } from '@google/genai';
import { Sequelize, DataTypes } from 'sequelize';
import fetch from 'node-fetch';
import { readFileSync } from 'node:fs';
import { initializeApp as initFirebase, cert } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

dotenv.config();

// Firebase Admin (FCM push). .env: FIREBASE_SERVICE_ACCOUNT=servis-hesabi-anahtari.json yolu
let fcm = null;
try {
    const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT;
    if (!keyPath) throw new Error('FIREBASE_SERVICE_ACCOUNT tanımlı değil');
    initFirebase({ credential: cert(JSON.parse(readFileSync(keyPath, 'utf8'))) });
    fcm = getMessaging();
    console.log('Firebase Admin hazır, push bildirimleri açık.');
} catch (err) {
    console.warn('Push bildirimleri kapalı:', err.message);
}

const app = express();
app.use(cors());
app.use(express.json());

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
const OPENWEATHER_KEY = process.env.OPENWEATHER_API_KEY;

// 1. Sequelize ile MySQL Bağlantısı
const sequelize = new Sequelize(
    process.env.DB_NAME,
    process.env.DB_USER,
    process.env.DB_PASS,
    {
        host: process.env.DB_HOST,
        port: process.env.DB_PORT || 3306,
        dialect: 'mysql',
        logging: false // Konsolu SQL sorgularıyla kirletmemek için
    }
);

// 2. Analitik Tablo Modeli (UsageAnalytics)
const UsageAnalytics = sequelize.define('UsageAnalytics', {
    locationName: {
        type: DataTypes.STRING,
        allowNull: false
    },
    analysisType: {
        type: DataTypes.STRING, // 'glass' veya 'car'
        allowNull: false
    },
    score: {
        type: DataTypes.INTEGER,
        allowNull: true
    }
}, {
    tableName: 'usage_analytics',
    timestamps: true // createdAt ve updatedAt otomatik eklenir
});

// 1. Yeni Model: Kullanıcı Limit Takibi
const UserLimit = sequelize.define('UserLimit', {
    deviceIdentifier: {
        type: DataTypes.STRING,
        allowNull: false,
        unique: true
    },
    dailyUsageCount: {
        type: DataTypes.INTEGER,
        defaultValue: 0
    },
    lastUsageDate: {
        type: DataTypes.STRING, // "YYYY-MM-DD" formatında gün tutacağız
        allowNull: true
    },
    isPremium: {
        type: DataTypes.BOOLEAN,
        defaultValue: false
    }
}, {
    tableName: 'user_limits',
    timestamps: true
});


// Veritabanı bağlantısını test et ve tabloları senkronize et
async function initDB() {
    try {
        await sequelize.authenticate();
        console.log('MySQL veritabanı bağlantısı başarılı.');
        await sequelize.sync(); // Tablo yoksa otomatik oluşturur
        console.log('Tablolar senkronize edildi.');
    } catch (error) {
        console.error('MySQL bağlantı hatası:', error);
    }
}
initDB();

// Günlük ücretsiz analiz hakkı. 0 = sınırsız (şimdilik varsayılan).
// Sınırı geri açmak için .env'e örn. DAILY_FREE_LIMIT=1 ekle.
const DAILY_FREE_LIMIT = Number(process.env.DAILY_FREE_LIMIT ?? 0);

async function checkAndConsumeLimit(deviceIdentifier) {
    const todayStr = new Date().toISOString().split('T')[0]; // "2026-09-24"

    let [userLimit] = await UserLimit.findOrCreate({
        where: { deviceIdentifier },
        defaults: { dailyUsageCount: 0, lastUsageDate: todayStr, isPremium: false }
    });

    // Eğer premiumsa sınırsız
    if (userLimit.isPremium) {
        return { allowed: true, isPremium: true };
    }

    // Eğer yeni bir güne girildiyse hakkı sıfırla
    if (userLimit.lastUsageDate !== todayStr) {
        userLimit.dailyUsageCount = 0;
        userLimit.lastUsageDate = todayStr;
    }

    // Günlük hak sınırı (0 ise sınır yok, kullanım yine sayılır)
    if (DAILY_FREE_LIMIT > 0 && userLimit.dailyUsageCount >= DAILY_FREE_LIMIT) {
        return { allowed: false, message: "Günlük ücretsiz hakkınız bitti!" };
    }

    // Kullanımı say ve kaydet
    userLimit.dailyUsageCount += 1;
    await userLimit.save();

    const remaining = DAILY_FREE_LIMIT > 0 ? DAILY_FREE_LIMIT - userLimit.dailyUsageCount : null;
    return { allowed: true, remaining };
}

// 3. Push Bildirimi Aboneliği (hatırlatmalar)
const PushSubscription = sequelize.define('PushSubscription', {
    deviceIdentifier: {
        type: DataTypes.STRING,
        allowNull: false,
        unique: true
    },
    pushToken: {
        type: DataTypes.STRING(512), // FCM kayıt token'ı
        allowNull: false
    },
    platform: DataTypes.STRING, // 'android' | 'ios'
    latitude: DataTypes.DOUBLE,
    longitude: DataTypes.DOUBLE,
    locationName: DataTypes.STRING,
    goodDay: {
        type: DataTypes.BOOLEAN, // "Uygun gün gelince haber ver"
        defaultValue: false
    },
    rainAfterWash: {
        type: DataTypes.BOOLEAN, // "Yıkadıktan sonra yağmur uyarısı"
        defaultValue: false
    },
    lastWashAt: {
        type: DataTypes.DATE,
        allowNull: true
    },
    rainWarnedWashAt: {
        type: DataTypes.DATE, // Hangi yıkama için yağmur uyarısı gönderildi (tekrar göndermemek için)
        allowNull: true
    },
    lastGoodDayDate: {
        type: DataTypes.STRING, // "YYYY-MM-DD" (İstanbul) — günde en fazla bir kez değerlendir
        allowNull: true
    }
}, {
    // Eski Expo tabanlı 'push_subscriptions' tablosu artık kullanılmıyor
    tableName: 'fcm_subscriptions',
    timestamps: true
});

// OpenWeather 5 günlük / 3 saatlik ham tahmin listesi
async function fetchForecastList(latitude, longitude) {
    const weatherUrl = `https://api.openweathermap.org/data/2.5/forecast?lat=${latitude}&lon=${longitude}&units=metric&lang=tr&appid=${OPENWEATHER_KEY}`;
    const weatherResponse = await fetch(weatherUrl);
    const weatherData = await weatherResponse.json();

    if (weatherData.cod !== "200") {
        throw new Error("Hava durumu servisinden veri alınamadı.");
    }
    return weatherData.list;
}

// Ortak Hava Verisi Çekme Fonksiyonu
async function getWeatherData(latitude, longitude) {
    const list = await fetchForecastList(latitude, longitude);

    const dailySummaryMap = {};
    list.forEach(item => {
        const datePart = item.dt_txt.split(' ')[0]; 
        
        if (!dailySummaryMap[datePart]) {
            const dateObj = new Date(datePart);
            const formattedDateName = new Intl.DateTimeFormat('tr-TR', { 
                timeZone: 'Europe/Istanbul', 
                day: 'numeric', 
                month: 'long', 
                weekday: 'long' 
            }).format(dateObj);

            dailySummaryMap[datePart] = {
                dateName: formattedDateName,
                temps: [],
                rainProbs: [],
                windSpeeds: [],
                humidities: [],
                weathers: []
            };
        }

        dailySummaryMap[datePart].temps.push(item.main.temp);
        dailySummaryMap[datePart].rainProbs.push(item.pop ? Math.round(item.pop * 100) : 0);
        dailySummaryMap[datePart].windSpeeds.push(Math.round(item.wind.speed * 3.6));
        dailySummaryMap[datePart].humidities.push(item.main.humidity);
        dailySummaryMap[datePart].weathers.push(item.weather[0].description);
    });

    return Object.values(dailySummaryMap).map(day => ({
        tarihVeGun: day.dateName,
        ortalamaSicaklik: Math.round(day.temps.reduce((a, b) => a + b, 0) / day.temps.length),
        maksimumYagisIhtimaliYuzde: Math.max(...day.rainProbs),
        maksimumRuzgarHiziKmS: Math.max(...day.windSpeeds),
        ortalamaNemYuzde: Math.round(day.humidities.reduce((a, b) => a + b, 0) / day.humidities.length),
        havaDurumuOzet: day.weathers[0]
    }));
};

// MySQL'e Log Atma Yardımcı Fonksiyonu
async function logToMySQL(locationName, analysisType, score) {
    try {
        await UsageAnalytics.create({
            locationName,
            analysisType,
            score
        });
    } catch (err) {
        console.error("MySQL loglama hatası:", err);
    }
}

// 1. CAM SİLME ANALİZİ
app.post('/api/analyze-weather', async (req, res) => {
    try {
        const { locationName, coords, deviceIdentifier } = req.body; 
        if (!coords?.latitude || !coords.longitude) return res.status(400).json({ error: "Koordinat bulunamadı." });
        if (!deviceIdentifier) return res.status(400).json({ error: "Cihaz kimliği eksik." });

        // Kullanıcı limitini kontrol et
        const limitCheck = await checkAndConsumeLimit(deviceIdentifier);
        if (!limitCheck.allowed) {
            return res.status(403).json({ limitExceeded: true, error: limitCheck.message });
        }

        const structuredDailyForecast = await getWeatherData(coords.latitude, coords.longitude);
        const todayFormatted = new Intl.DateTimeFormat('tr-TR', { timeZone: 'Europe/Istanbul', dateStyle: 'full' }).format(new Date());

        const prompt = `
            Bugünün tarihi: ${todayFormatted}.
            Konum: ${locationName}.
            Günlük hava tahmin tablosu: ${JSON.stringify(structuredDailyForecast)}
            
            Bu verilere göre CAM SİLME analizi yap. Rüzgar 25 km/s üzerindeyse veya yağmur %30'dan fazlaysa cam silinmez.
            SADECE geçerli bir JSON formatında şu anahtarlarla yanıt ver:
            {
              "todaySummary": "Bugünkü hava özeti",
              "bestDay": "En ideal cam silme günü",
              "score": Puan (0-100),
              "summary": "Esprili özet cümle",
              "reason": "Rüzgar, yağmur ve nem detaylarıyla gerekçe."
            }
        `;

        const aiResponse = await ai.models.generateContent({ model: 'gemini-3.5-flash-lite', contents: prompt, config: { responseMimeType: 'application/json' } });
        let cleanText = aiResponse.text.trim().replace(/^```json/, "").replace(/^```/, "").replace(/```$/, "").trim();
        const resultJson = JSON.parse(cleanText);

        // MySQL'e logla
        logToMySQL(locationName, 'glass', resultJson.score);

        res.json(resultJson);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: "Analiz sırasında hata oluştu." });
    }
});

// 2. ARABA YIKAMA ANALİZİ
app.post('/api/analyze-car-wash', async (req, res) => {
    try {
        const { locationName, coords, deviceIdentifier } = req.body; 
        if (!coords?.latitude || !coords.longitude) return res.status(400).json({ error: "Koordinat bulunamadı." });

        if (!deviceIdentifier) return res.status(400).json({ error: "Cihaz kimliği eksik." });

        // Hak kontrolü
        const limitCheck = await checkAndConsumeLimit(deviceIdentifier);
        if (!limitCheck.allowed) {
            return res.status(403).json({ limitExceeded: true, error: limitCheck.message });
        }

        const structuredDailyForecast = await getWeatherData(coords.latitude, coords.longitude);
        const todayFormatted = new Intl.DateTimeFormat('tr-TR', { timeZone: 'Europe/Istanbul', dateStyle: 'full' }).format(new Date());

        const prompt = `
            Bugünün tarihi: ${todayFormatted}.
            Oto yıkama analistisin. Konum: ${locationName}.
            Günlük hava tahmin tablosu: ${JSON.stringify(structuredDailyForecast)}

            Bu verilere dayanarak ARABA YIKAMA analizi yap. Güneş sıcaklığı, su lekesi riski, rüzgar ve yağmuru değerlendir.
            SADECE geçerli bir JSON formatında şu anahtarlarla yanıt ver:
            {
              "todaySummary": "Bugün araba yıkanır mı özeti",
              "bestDay": "En ideal araba yıkatmak günü",
              "score": Puan (0-100),
              "summary": "Esprili özet cümle",
              "reason": "Güneş, sıcaklık, su lekesi ve yağmur detaylarıyla gerekçe."
            }
        `;

        const aiResponse = await ai.models.generateContent({ model: 'gemini-3.5-flash-lite', contents: prompt, config: { responseMimeType: 'application/json' } });
        let cleanText = aiResponse.text.trim().replace(/^```json/, "").replace(/^```/, "").replace(/```$/, "").trim();
        const resultJson = JSON.parse(cleanText);

        // MySQL'e logla
        logToMySQL(locationName, 'car', resultJson.score);

        res.json(resultJson);
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: "Araba yıkama analizi sırasında hata oluştu." });
    }
});

// ================= PUSH BİLDİRİMLERİ =================

const ANDROID_CHANNEL_ID = 'reminders'; // Mobil uygulamadaki kanal adıyla aynı olmalı
const GOOD_DAY_THRESHOLD = 80;
const RAIN_WARN_POP = 0.5;              // %50 ve üzeri yağış ihtimali uyarı sebebi
const HOUR = 60 * 60 * 1000;

function isFcmToken(token) {
    return typeof token === 'string' && token.length >= 32 && token.length <= 512 && !/\s/.test(token);
}

// İstanbul saatine göre bugünün tarihi ("YYYY-MM-DD") ve saati
function istanbulNow() {
    const parts = Object.fromEntries(
        new Intl.DateTimeFormat('en-CA', {
            timeZone: 'Europe/Istanbul', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23'
        }).formatToParts(new Date()).map(p => [p.type, p.value])
    );
    return { date: `${parts.year}-${parts.month}-${parts.day}`, hour: Number(parts.hour) };
}

// Bu hatalar token'ın artık geçersiz olduğunu gösterir → aboneliği sil
const DEAD_TOKEN_ERRORS = new Set([
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token'
]);

// { to, title, body, data } mesajlarını FCM'e gönderir (500'lük parçalar).
// Her mesaj için { to, ok, messageId?, error? } döndürür.
async function sendPush(messages) {
    if (!fcm) {
        console.warn('Push gönderilemedi: Firebase Admin hazır değil.');
        return messages.map(m => ({ to: m.to, ok: false, error: 'firebase-admin-not-configured' }));
    }
    const results = [];
    for (let i = 0; i < messages.length; i += 500) {
        const chunk = messages.slice(i, i + 500);
        const fcmMessages = chunk.map(m => ({
            token: m.to,
            notification: { title: m.title, body: m.body },
            // FCM data değerleri string olmalı
            data: Object.fromEntries(Object.entries(m.data || {}).map(([k, v]) => [k, String(v)])),
            android: { priority: 'high', notification: { channelId: ANDROID_CHANNEL_ID } },
            apns: { payload: { aps: { sound: 'default' } } }
        }));
        try {
            const batch = await fcm.sendEach(fcmMessages);
            batch.responses.forEach((r, idx) => {
                const to = chunk[idx].to;
                if (r.success) {
                    results.push({ to, ok: true, messageId: r.messageId });
                    return;
                }
                const code = r.error?.code;
                console.error('Push hatası:', code, r.error?.message);
                results.push({ to, ok: false, error: code || r.error?.message });
                if (DEAD_TOKEN_ERRORS.has(code)) {
                    PushSubscription.destroy({ where: { pushToken: to } }).catch(() => {});
                }
            });
        } catch (err) {
            // Kimlik bilgisi / proje hatası gibi tüm grubu etkileyen durumlar
            console.error('FCM isteği başarısız:', err.code, err.message);
            chunk.forEach(m => results.push({ to: m.to, ok: false, error: err.code || err.message }));
        }
    }
    return results;
}

// Aynı çalışma içinde yakın konumlar için hava durumunu bir kez çek
function forecastCache() {
    const cache = new Map();
    return (lat, lon) => {
        const key = `${lat.toFixed(2)},${lon.toFixed(2)}`;
        if (!cache.has(key)) cache.set(key, fetchForecastList(lat, lon));
        return cache.get(key);
    };
}

// Kural tabanlı skor (Gemini maliyeti olmadan): önümüzdeki 36 saatte yağış ve 12 saatte rüzgar
function ruleBasedScore(list, now = Date.now()) {
    const within = (h) => list.filter(it => it.dt * 1000 >= now - 3 * HOUR && it.dt * 1000 <= now + h * HOUR);
    const maxPop = Math.max(0, ...within(36).map(it => it.pop || 0));
    const maxWindKmh = Math.max(0, ...within(12).map(it => (it.wind?.speed || 0) * 3.6));
    const score = 100 - Math.round(maxPop * 100) - Math.max(0, Math.round((maxWindKmh - 15) * 2));
    return { score: Math.max(0, Math.min(100, score)), maxPop, maxWindKmh: Math.round(maxWindKmh) };
}

// Belirli bir zaman aralığında ilk yüksek yağış ihtimali olan dilim
function firstRainBetween(list, from, to) {
    return list.find(it => it.dt * 1000 >= from && it.dt * 1000 <= to && (it.pop || 0) >= RAIN_WARN_POP) || null;
}

function formatSlot(unixSeconds) {
    return new Intl.DateTimeFormat('tr-TR', {
        timeZone: 'Europe/Istanbul', weekday: 'long', hour: '2-digit', minute: '2-digit'
    }).format(new Date(unixSeconds * 1000));
}

// "Uygun gün gelince haber ver" — her sabah bir kez
async function runGoodDayJob() {
    const { date } = istanbulNow();
    const subs = await PushSubscription.findAll({ where: { goodDay: true } });
    const getForecast = forecastCache();
    const messages = [];

    for (const sub of subs) {
        if (sub.lastGoodDayDate === date || sub.latitude == null || sub.longitude == null) continue;
        try {
            const { score } = ruleBasedScore(await getForecast(sub.latitude, sub.longitude));
            if (score >= GOOD_DAY_THRESHOLD) {
                messages.push({
                    to: sub.pushToken,
                    title: 'Bugün tam yıkama günü ☀️',
                    body: `${sub.locationName || 'Konumunda'} bugün skor ${score}. Aracını yıkamak ve camları silmek için uygun.`,
                    data: { type: 'goodDay', score }
                });
            }
            sub.lastGoodDayDate = date;
            await sub.save();
        } catch (err) {
            console.error('Uygun gün kontrolü hatası:', err.message);
        }
    }
    if (messages.length) await sendPush(messages);
}

// "Yıkadıktan sonra yağmur uyarısı" — yıkamadan sonraki 48 saat içinde yağmur var mı?
async function checkRainAfterWash(sub, getForecast = forecastCache()) {
    if (!sub.rainAfterWash || !sub.lastWashAt || sub.latitude == null || sub.longitude == null) return null;
    const washAt = new Date(sub.lastWashAt).getTime();
    const now = Date.now();
    if (now > washAt + 48 * HOUR) return null;
    if (sub.rainWarnedWashAt && new Date(sub.rainWarnedWashAt).getTime() === washAt) return null;

    const rain = firstRainBetween(await getForecast(sub.latitude, sub.longitude), now, washAt + 48 * HOUR);
    if (!rain) return null;

    sub.rainWarnedWashAt = sub.lastWashAt;
    await sub.save();
    return {
        to: sub.pushToken,
        title: 'Yağmur geliyor 🌧️',
        body: `${formatSlot(rain.dt)} civarı %${Math.round(rain.pop * 100)} yağış ihtimali var. Aracını kapalı alana çekmek isteyebilirsin.`,
        data: { type: 'rainAfterWash' }
    };
}

async function runRainAfterWashJob() {
    const subs = await PushSubscription.findAll({ where: { rainAfterWash: true } });
    const getForecast = forecastCache();
    const messages = [];
    for (const sub of subs) {
        try {
            const msg = await checkRainAfterWash(sub, getForecast);
            if (msg) messages.push(msg);
        } catch (err) {
            console.error('Yağmur uyarısı kontrolü hatası:', err.message);
        }
    }
    if (messages.length) await sendPush(messages);
}

// Cihaz push token'ını ve hatırlatma tercihlerini kaydet / güncelle
app.post('/api/push/register', async (req, res) => {
    try {
        const { deviceIdentifier, pushToken, platform, coords, locationName, goodDay, rainAfterWash, lastWashAt } = req.body;
        if (!deviceIdentifier) return res.status(400).json({ error: "Cihaz kimliği eksik." });
        if (!isFcmToken(pushToken)) return res.status(400).json({ error: "Geçersiz push token." });

        const [sub] = await PushSubscription.findOrCreate({ where: { deviceIdentifier }, defaults: { pushToken } });
        sub.pushToken = pushToken;
        if (platform === 'android' || platform === 'ios') sub.platform = platform;
        if (coords?.latitude != null && coords?.longitude != null) {
            sub.latitude = coords.latitude;
            sub.longitude = coords.longitude;
        }
        if (locationName) sub.locationName = locationName;
        if (typeof goodDay === 'boolean') sub.goodDay = goodDay;
        if (typeof rainAfterWash === 'boolean') sub.rainAfterWash = rainAfterWash;
        // Abone olmadan önce "Bugün yıkadım" denmişse o yıkamayı da hesaba kat
        const washAt = lastWashAt ? new Date(lastWashAt) : null;
        if (washAt && !isNaN(washAt) && washAt <= new Date() && (!sub.lastWashAt || washAt > sub.lastWashAt)) {
            sub.lastWashAt = washAt;
        }
        await sub.save();

        res.json({ ok: true });
    } catch (error) {
        console.error(error);
        res.status(500).json({ error: "Bildirim kaydı sırasında hata oluştu." });
    }
});

// "Bugün yıkadım" — yıkama zamanını kaydet ve hemen yağmur kontrolü yap
app.post('/api/push/wash', async (req, res) => {
    try {
        const { deviceIdentifier } = req.body;
        if (!deviceIdentifier) return res.status(400).json({ error: "Cihaz kimliği eksik." });

        const sub = await PushSubscription.findOne({ where: { deviceIdentifier } });
        if (!sub) return res.json({ ok: true, subscribed: false });

        sub.lastWashAt = new Date();
        await sub.save();
        res.json({ ok: true, subscribed: true });

        const msg = await checkRainAfterWash(sub);
        if (msg) await sendPush([msg]);
    } catch (error) {
        console.error(error);
        if (!res.headersSent) res.status(500).json({ error: "Yıkama kaydı sırasında hata oluştu." });
    }
});

// ---------- Yalnızca geliştirme: push test uç noktaları ----------
// NODE_ENV=production iken kapalıdır.
if (process.env.NODE_ENV !== 'production') {
    // Kayıtlı cihazları listele (token kısaltılmış)
    app.get('/api/push/subscriptions', async (req, res) => {
        const subs = await PushSubscription.findAll({ order: [['updatedAt', 'DESC']] });
        res.json(subs.map(s => ({
            deviceIdentifier: s.deviceIdentifier,
            platform: s.platform,
            token: `${s.pushToken.slice(0, 20)}…`,
            locationName: s.locationName,
            coords: s.latitude != null ? { latitude: s.latitude, longitude: s.longitude } : null,
            goodDay: s.goodDay,
            rainAfterWash: s.rainAfterWash,
            lastWashAt: s.lastWashAt,
            updatedAt: s.updatedAt
        })));
    });

    // Test bildirimi gönder.
    // body: { deviceIdentifier?: string, mode?: 'simple' | 'goodDay' | 'rain' }
    // deviceIdentifier verilmezse kayıtlı tüm cihazlara gönderir.
    app.post('/api/push/test', async (req, res) => {
        try {
            const { deviceIdentifier, mode = 'simple' } = req.body || {};
            if (!['simple', 'goodDay', 'rain'].includes(mode)) {
                return res.status(400).json({ error: "mode 'simple', 'goodDay' veya 'rain' olmalı." });
            }
            const subs = await PushSubscription.findAll(deviceIdentifier ? { where: { deviceIdentifier } } : {});
            if (!subs.length) return res.status(404).json({ error: "Kayıtlı cihaz yok. Önce uygulamada bir push hatırlatmasını aç." });

            const getForecast = forecastCache();
            const messages = [];
            for (const sub of subs) {
                const base = { to: sub.pushToken, data: { type: 'test', mode } };
                if (mode === 'simple') {
                    messages.push({ ...base, title: 'Parla test bildirimi 🔔', body: 'Push bildirimleri çalışıyor.' });
                    continue;
                }
                if (sub.latitude == null || sub.longitude == null) {
                    messages.push({ ...base, title: 'Parla test', body: 'Bu cihaz için kayıtlı konum yok.' });
                    continue;
                }
                const list = await getForecast(sub.latitude, sub.longitude);
                if (mode === 'goodDay') {
                    const { score, maxPop, maxWindKmh } = ruleBasedScore(list);
                    const good = score >= GOOD_DAY_THRESHOLD;
                    messages.push({
                        ...base,
                        title: good ? '[Test] Bugün tam yıkama günü ☀️' : `[Test] Bugün uygun değil (skor ${score})`,
                        body: `${sub.locationName || 'Konum'}: skor ${score}, yağış en fazla %${Math.round(maxPop * 100)}, rüzgar ${maxWindKmh} km/s. Eşik ${GOOD_DAY_THRESHOLD}.`
                    });
                } else {
                    const rain = firstRainBetween(list, Date.now(), Date.now() + 48 * HOUR);
                    messages.push({
                        ...base,
                        title: rain ? '[Test] Yağmur geliyor 🌧️' : '[Test] 48 saatte yağmur yok',
                        body: rain
                            ? `${formatSlot(rain.dt)} civarı %${Math.round(rain.pop * 100)} yağış ihtimali var.`
                            : `${sub.locationName || 'Konum'} için önümüzdeki 48 saatte %${Math.round(RAIN_WARN_POP * 100)} üzeri yağış beklenmiyor.`
                    });
                }
            }

            // FCM hataları (geçersiz token, yetki sorunu) doğrudan yanıtta döner
            const sent = await sendPush(messages);
            res.json({
                mode,
                results: sent.map(r => ({
                    token: `${r.to.slice(0, 20)}…`,
                    ok: r.ok,
                    messageId: r.messageId,
                    error: r.error
                }))
            });
        } catch (error) {
            console.error(error);
            res.status(500).json({ error: "Test bildirimi gönderilemedi.", detail: error.message });
        }
    });
}

// Zamanlayıcı: 10 dakikada bir kontrol. Uygun gün 08:00–10:59 arası günde bir kez,
// yağmur uyarısı 3 saatte bir.
let lastRainJobAt = 0;
setInterval(async () => {
    try {
        const { hour } = istanbulNow();
        if (hour >= 8 && hour < 11) await runGoodDayJob();
        if (Date.now() - lastRainJobAt >= 3 * HOUR) {
            lastRainJobAt = Date.now();
            await runRainAfterWashJob();
        }
    } catch (err) {
        console.error('Bildirim zamanlayıcısı hatası:', err);
    }
}, 10 * 60 * 1000);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Backend ${PORT} portunda MySQL (Sequelize) analitiği ile ayakta!`));