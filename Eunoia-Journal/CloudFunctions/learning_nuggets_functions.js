const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();
const db = admin.firestore();

// Konfiguration
const NUGGETS_PER_CATEGORY = 25;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;
const LLM_PROVIDER = 'deepseek'; // 'openai' oder 'deepseek'

// Kategorien für Learning Nuggets
const CATEGORIES = [
    'Persönliches Wachstum',
    'Beziehungen',
    'Gesundheit',
    'Produktivität',
    'Finanzen',
    'Kreativität',
    'Achtsamkeit',
    'Karriere'
];

/**
 * Initialisiert die Datenbank mit Learning Nuggets für alle Kategorien
 */
exports.initializeNuggetsForAllCategories = functions.https.onRequest(async (req, res) => {
    try {
        console.log('Initialisiere Learning Nuggets für alle Kategorien');
        
        let totalGenerated = 0;
        
        for (const category of CATEGORIES) {
            console.log(`Generiere Nuggets für Kategorie: ${category}`);
            
            // Prüfe, ob bereits Nuggets für diese Kategorie existieren
            const existingNuggets = await db.collection('learning_nuggets')
                .where('category', '==', category)
                .limit(1)
                .get();
            
            if (!existingNuggets.empty) {
                console.log(`Kategorie ${category} hat bereits Nuggets, überspringe`);
                continue;
            }
            
            // Generiere neue Nuggets für diese Kategorie
            const newNuggets = await generateNuggetsForCategory(category, NUGGETS_PER_CATEGORY);
            
            // Speichere die Nuggets in Firestore
            const batch = db.batch();
            
            for (const nugget of newNuggets) {
                const docRef = db.collection('learning_nuggets').doc();
                batch.set(docRef, {
                    id: docRef.id,
                    category: category,
                    title: nugget.title,
                    content: nugget.content,
                    created_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }
            
            await batch.commit();
            
            totalGenerated += newNuggets.length;
            console.log(`Erfolgreich ${newNuggets.length} Nuggets für Kategorie ${category} generiert`);
        }
        
        res.status(200).send(`Initialisierung abgeschlossen: ${totalGenerated} Nuggets generiert`);
    } catch (error) {
        console.error('Fehler bei der Initialisierung:', error);
        res.status(500).send(`Fehler bei der Initialisierung: ${error.message}`);
    }
});

/**
 * Generiert neue Nuggets für eine Kategorie, wenn ein Benutzer alle vorhandenen Nuggets verbraucht hat
 */
exports.generateNewNuggets = functions.https.onRequest(async (req, res) => {
    try {
        const category = req.query.category;
        
        if (!category || !CATEGORIES.includes(category)) {
            return res.status(400).send('Ungültige oder fehlende Kategorie');
        }
        
        console.log(`Generiere neue Nuggets für Kategorie: ${category}`);
        
        // Generiere neue Nuggets für diese Kategorie
        const newNuggets = await generateNuggetsForCategory(category, NUGGETS_PER_CATEGORY);
        
        // Speichere die Nuggets in Firestore
        const batch = db.batch();
        
        for (const nugget of newNuggets) {
            const docRef = db.collection('learning_nuggets').doc();
            batch.set(docRef, {
                id: docRef.id,
                category: category,
                title: nugget.title,
                content: nugget.content,
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });
        }
        
        await batch.commit();
        
        res.status(200).send(`Erfolgreich ${newNuggets.length} neue Nuggets für Kategorie ${category} generiert`);
    } catch (error) {
        console.error('Fehler bei der Generierung:', error);
        res.status(500).send(`Fehler bei der Generierung: ${error.message}`);
    }
});

/**
 * Generiert Nuggets für eine Kategorie mit dem konfigurierten LLM-Provider
 * @param {string} category - Die Kategorie, für die Nuggets generiert werden sollen
 * @param {number} count - Die Anzahl der zu generierenden Nuggets
 * @returns {Array} - Die generierten Nuggets
 */
async function generateNuggetsForCategory(category, count) {
    console.log(`Generiere ${count} Nuggets für Kategorie ${category} mit Provider ${LLM_PROVIDER}`);
    
    // Erstelle den Prompt für die KI
    const prompt = createPromptForBatchGeneration(category, count);
    
    // Generiere den Text mit dem konfigurierten Provider
    let response;
    if (LLM_PROVIDER === 'openai') {
        response = await generateTextWithOpenAI(prompt);
    } else if (LLM_PROVIDER === 'deepseek') {
        response = await generateTextWithDeepSeek(prompt);
    } else {
        throw new Error(`Ungültiger LLM-Provider: ${LLM_PROVIDER}`);
    }
    
    // Parse die Antwort und erstelle die Nuggets
    return parseNuggetsFromResponse(response, category);
}

/**
 * Erstellt einen Prompt für die Batch-Generierung von Learning Nuggets
 * @param {string} category - Die Kategorie, für die Nuggets generiert werden sollen
 * @param {number} count - Die Anzahl der zu generierenden Nuggets
 * @returns {string} - Der Prompt für die KI
 */
function createPromptForBatchGeneration(category, count) {
    return `
Generiere ${count} einzigartige, prägnante und lehrreiche Learning Nuggets zum Thema "${category}".

Anforderungen:
- Jedes Nugget sollte faktenbasiert und überprüfbar sein
- Verwende einfache Sprache und sorge für hohe Verständlichkeit
- Jedes Nugget sollte maximal 3 Sätze lang sein und ein Aha-Erlebnis erzeugen
- Jedes Nugget sollte einen kurzen, prägnanten Titel haben

Ausgabeformat:
Formatiere die Ausgabe als nummerierte Liste mit Titel und Inhalt für jedes Nugget:

1. Titel: [Titel des ersten Nuggets]
Inhalt: [Inhalt des ersten Nuggets]

2. Titel: [Titel des zweiten Nuggets]
Inhalt: [Inhalt des zweiten Nuggets]

usw.
`;
}

/**
 * Generiert Text mit der OpenAI API
 * @param {string} prompt - Der Prompt für die Textgenerierung
 * @returns {string} - Der generierte Text
 */
async function generateTextWithOpenAI(prompt) {
    try {
        const response = await axios.post(
            'https://api.openai.com/v1/chat/completions',
            {
                model: 'gpt-4',
                messages: [
                    { role: 'system', content: 'Du bist ein hilfreicher Assistent für Journaling und Selbstreflexion.' },
                    { role: 'user', content: prompt }
                ],
                temperature: 0.7,
                max_tokens: 2000
            },
            {
                headers: {
                    'Authorization': `Bearer ${OPENAI_API_KEY}`,
                    'Content-Type': 'application/json'
                }
            }
        );
        
        return response.data.choices[0].message.content;
    } catch (error) {
        console.error('Fehler bei der OpenAI API:', error.response?.data || error.message);
        throw new Error(`OpenAI API-Fehler: ${error.message}`);
    }
}

/**
 * Generiert Text mit der DeepSeek API
 * @param {string} prompt - Der Prompt für die Textgenerierung
 * @returns {string} - Der generierte Text
 */
async function generateTextWithDeepSeek(prompt) {
    try {
        const response = await axios.post(
            'https://api.deepseek.com/v1/chat/completions',
            {
                model: 'deepseek-chat',
                messages: [
                    { role: 'user', content: prompt }
                ],
                temperature: 0.7,
                max_tokens: 2000
            },
            {
                headers: {
                    'Authorization': DEEPSEEK_API_KEY,
                    'Content-Type': 'application/json'
                }
            }
        );
        
        return response.data.choices[0].message.content;
    } catch (error) {
        console.error('Fehler bei der DeepSeek API:', error.response?.data || error.message);
        throw new Error(`DeepSeek API-Fehler: ${error.message}`);
    }
}

/**
 * Parst die Antwort der KI und erstellt daraus Learning Nuggets
 * @param {string} response - Die Antwort der KI
 * @param {string} category - Die Kategorie der Nuggets
 * @returns {Array} - Die erstellten Nuggets
 */
function parseNuggetsFromResponse(response, category) {
    const nuggets = [];
    
    // Teile die Antwort in Zeilen auf
    const lines = response.split('\n');
    
    let currentTitle = null;
    let currentContent = null;
    
    for (const line of lines) {
        const trimmedLine = line.trim();
        
        // Überspringe leere Zeilen
        if (!trimmedLine) {
            continue;
        }
        
        // Suche nach Titelzeilen (Format: "X. Titel: [Titel]" oder "Titel: [Titel]")
        if (trimmedLine.includes('Titel:')) {
            // Wenn wir bereits einen Titel haben, speichere das vorherige Nugget
            if (currentTitle && currentContent) {
                nuggets.push({
                    title: currentTitle,
                    content: currentContent
                });
            }
            
            // Extrahiere den neuen Titel
            const titleMatch = trimmedLine.match(/Titel:\s*(.*)/);
            if (titleMatch) {
                currentTitle = titleMatch[1].trim();
                currentContent = null;
            }
        }
        // Suche nach Inhaltszeilen (Format: "Inhalt: [Inhalt]")
        else if (trimmedLine.includes('Inhalt:')) {
            const contentMatch = trimmedLine.match(/Inhalt:\s*(.*)/);
            if (contentMatch) {
                currentContent = contentMatch[1].trim();
            }
            
            // Wenn wir sowohl Titel als auch Inhalt haben, speichere das Nugget
            if (currentTitle && currentContent) {
                nuggets.push({
                    title: currentTitle,
                    content: currentContent
                });
                
                // Setze die Werte zurück
                currentTitle = null;
                currentContent = null;
            }
        }
    }
    
    // Füge das letzte Nugget hinzu, falls vorhanden
    if (currentTitle && currentContent) {
        nuggets.push({
            title: currentTitle,
            content: currentContent
        });
    }
    
    return nuggets;
} 