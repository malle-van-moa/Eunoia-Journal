const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

/**
 * Cloud Function zum Generieren neuer Learning Nuggets
 * 
 * Diese Funktion wird aufgerufen, wenn neue Learning Nuggets generiert werden sollen.
 * Sie kann entweder manuell oder durch einen Trigger ausgelöst werden.
 * 
 * @param {Object} data - Die Daten für die Generierung
 * @param {string} data.category - Die Kategorie der zu generierenden Nuggets
 * @param {number} data.count - Die Anzahl der zu generierenden Nuggets (Standard: 5)
 * @param {string} data.model - Das zu verwendende KI-Modell (openai oder deepseek)
 * @returns {Object} - Ein Objekt mit der Anzahl der generierten Nuggets
 */
exports.generateLearningNuggets = functions.https.onCall(async (data, context) => {
  // Überprüfe, ob der Benutzer authentifiziert ist
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Die Funktion erfordert Authentifizierung."
    );
  }
  
  // Extrahiere die Parameter
  const category = data.category;
  const count = data.count || 5;
  const model = data.model || "openai";
  
  // Überprüfe, ob eine Kategorie angegeben wurde
  if (!category) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Es muss eine Kategorie angegeben werden."
    );
  }
  
  // Hole die API-Schlüssel aus den Umgebungsvariablen
  const openaiApiKey = functions.config().openai?.apikey;
  const deepseekApiKey = functions.config().deepseek?.apikey;
  
  // Überprüfe, ob der API-Schlüssel für das gewählte Modell verfügbar ist
  if (model === "openai" && !openaiApiKey) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "OpenAI API-Schlüssel ist nicht konfiguriert."
    );
  }
  
  if (model === "deepseek" && !deepseekApiKey) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "DeepSeek API-Schlüssel ist nicht konfiguriert."
    );
  }
  
  try {
    // Generiere die Learning Nuggets
    const generatedNuggets = await generateNuggets(category, count, model, openaiApiKey, deepseekApiKey);
    
    // Speichere die generierten Nuggets in Firestore
    const batch = admin.firestore().batch();
    
    for (const nugget of generatedNuggets) {
      const docRef = admin.firestore().collection("learning_nuggets").doc();
      batch.set(docRef, {
        id: docRef.id,
        category: category,
        title: nugget.title,
        content: nugget.content,
        created_at: admin.firestore.FieldValue.serverTimestamp()
      });
    }
    
    await batch.commit();
    
    functions.logger.info(`${generatedNuggets.length} Learning Nuggets für Kategorie ${category} generiert`);
    
    return { count: generatedNuggets.length };
  } catch (error) {
    functions.logger.error("Fehler beim Generieren von Learning Nuggets:", error);
    
    throw new functions.https.HttpsError(
      "internal",
      `Fehler beim Generieren von Learning Nuggets: ${error.message}`
    );
  }
});

/**
 * Generiert Learning Nuggets mit Hilfe eines KI-Modells
 * 
 * @param {string} category - Die Kategorie der zu generierenden Nuggets
 * @param {number} count - Die Anzahl der zu generierenden Nuggets
 * @param {string} model - Das zu verwendende KI-Modell (openai oder deepseek)
 * @param {string} openaiApiKey - Der OpenAI API-Schlüssel
 * @param {string} deepseekApiKey - Der DeepSeek API-Schlüssel
 * @returns {Array} - Ein Array mit den generierten Nuggets
 */
async function generateNuggets(category, count, model, openaiApiKey, deepseekApiKey) {
  // Erstelle den Prompt für die KI
  const prompt = `Generiere ${count} kurze, informative Learning Nuggets für die Kategorie "${category}". 
  
Jedes Nugget sollte einen Titel und einen Inhalt haben. Der Inhalt sollte etwa 2-3 Sätze umfassen und eine wertvolle Erkenntnis oder Information vermitteln.

Formatiere die Ausgabe als JSON-Array mit Objekten, die die Eigenschaften "title" und "content" enthalten.

Beispiel:
[
  {
    "title": "Die Kraft der Gewohnheit",
    "content": "Gewohnheiten formen etwa 40% unserer täglichen Handlungen. Durch bewusstes Etablieren positiver Gewohnheiten können wir unsere Produktivität und unser Wohlbefinden erheblich steigern."
  }
]`;

  // Wähle das KI-Modell und generiere die Nuggets
  if (model === "openai") {
    return await generateWithOpenAI(prompt, openaiApiKey);
  } else if (model === "deepseek") {
    return await generateWithDeepSeek(prompt, deepseekApiKey);
  } else {
    throw new Error(`Unbekanntes Modell: ${model}`);
  }
}

/**
 * Generiert Learning Nuggets mit OpenAI
 * 
 * @param {string} prompt - Der Prompt für die KI
 * @param {string} apiKey - Der OpenAI API-Schlüssel
 * @returns {Array} - Ein Array mit den generierten Nuggets
 */
async function generateWithOpenAI(prompt, apiKey) {
  const response = await axios.post(
    "https://api.openai.com/v1/chat/completions",
    {
      model: "gpt-4o",
      messages: [
        { role: "system", content: "Du bist ein Experte für die Erstellung von kurzen, informativen Learning Nuggets." },
        { role: "user", content: prompt }
      ],
      temperature: 0.7
    },
    {
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      }
    }
  );
  
  const content = response.data.choices[0].message.content;
  
  try {
    // Extrahiere das JSON aus der Antwort
    const jsonMatch = content.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    } else {
      throw new Error("Konnte kein JSON in der Antwort finden");
    }
  } catch (error) {
    functions.logger.error("Fehler beim Parsen der OpenAI-Antwort:", error);
    functions.logger.info("OpenAI-Antwort:", content);
    throw new Error("Fehler beim Parsen der OpenAI-Antwort");
  }
}

/**
 * Generiert Learning Nuggets mit DeepSeek
 * 
 * @param {string} prompt - Der Prompt für die KI
 * @param {string} apiKey - Der DeepSeek API-Schlüssel
 * @returns {Array} - Ein Array mit den generierten Nuggets
 */
async function generateWithDeepSeek(prompt, apiKey) {
  const response = await axios.post(
    "https://api.deepseek.com/v1/chat/completions",
    {
      model: "deepseek-chat",
      messages: [
        { role: "system", content: "Du bist ein Experte für die Erstellung von kurzen, informativen Learning Nuggets." },
        { role: "user", content: prompt }
      ],
      temperature: 0.7
    },
    {
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      }
    }
  );
  
  const content = response.data.choices[0].message.content;
  
  try {
    // Extrahiere das JSON aus der Antwort
    const jsonMatch = content.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    } else {
      throw new Error("Konnte kein JSON in der Antwort finden");
    }
  } catch (error) {
    functions.logger.error("Fehler beim Parsen der DeepSeek-Antwort:", error);
    functions.logger.info("DeepSeek-Antwort:", content);
    throw new Error("Fehler beim Parsen der DeepSeek-Antwort");
  }
} 