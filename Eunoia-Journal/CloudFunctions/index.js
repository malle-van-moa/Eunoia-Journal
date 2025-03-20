// Importiere die Cloud Functions aus der generateLearningNuggets.js-Datei
const learningNuggetsFunctions = require("./generateLearningNuggets");

// Exportiere die Cloud Functions
exports.generateLearningNuggets = learningNuggetsFunctions.generateLearningNuggets; 